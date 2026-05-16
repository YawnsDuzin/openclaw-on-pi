#!/usr/bin/env bash
# USAGE: bash scripts/collect-logs.sh > input.txt
#
# journalctl + (선택) 애플리케이션 로그를 수집해 stdout 으로.
# 출력 한 줄 형식:
#   <ISO-8601 ts> <unit-or-_> <severity> <message>
#
# 마스킹: 이메일 / IPv4 / Bearer 토큰 / 한국 휴대전화 / 신용카드 추정 패턴 / Authorization 헤더
#
# 환경변수:
#   LOG_TRIAGE_SINCE     기본 "1 hour ago"
#   LOG_TRIAGE_PRIORITY  기본 warning  (journalctl -p 형식, 예: warning, err, "warning..err")
#   LOG_TRIAGE_UNITS     콤마 구분 유닛 필터, 비우면 전체
#   LOG_TRIAGE_EXTRA     추가로 cat 할 로그 파일 경로 (콤마 구분, 선택)

set -euo pipefail

SINCE="${LOG_TRIAGE_SINCE:-1 hour ago}"
PRIORITY="${LOG_TRIAGE_PRIORITY:-warning}"
UNITS="${LOG_TRIAGE_UNITS:-}"
EXTRA="${LOG_TRIAGE_EXTRA:-}"

# ---------- journalctl 인자 조립 -------------------------------------------
JCTL_ARGS=(
    --since "$SINCE"
    -p "$PRIORITY"
    --output=json
    --no-pager
    --quiet
)
if [[ -n "$UNITS" ]]; then
    IFS=',' read -ra UA <<< "$UNITS"
    for u in "${UA[@]}"; do
        JCTL_ARGS+=(-u "$u")
    done
fi

# ---------- 마스킹 함수 -----------------------------------------------------
mask() {
    sed -E \
        -e 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g' \
        -e 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/<ip>/g' \
        -e 's/(Bearer|Token|Authorization:[[:space:]]*Bearer)[[:space:]]+[A-Za-z0-9._\-]+/\1 <token>/g' \
        -e 's/\b01[0-9]-?[0-9]{3,4}-?[0-9]{4}\b/<phone>/g' \
        -e 's/\b[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}[- ]?[0-9]{4}\b/<card>/g' \
        -e 's|/home/[^/[:space:]]+|/home/USER|g' \
        -e 's|(sk-[A-Za-z0-9]{20,})|<api-key>|g' \
        -e 's|(ghp_[A-Za-z0-9]{20,})|<gh-token>|g' \
        -e 's|(eyJ[A-Za-z0-9._\-]{20,})|<jwt>|g'
}

# ---------- 1. journalctl -> 정규화 -----------------------------------------
if command -v journalctl >/dev/null 2>&1; then
    journalctl "${JCTL_ARGS[@]}" 2>/dev/null \
        | jq -r '
            # PRIORITY: 0=emerg ... 7=debug
            (.PRIORITY // "6") as $pri
            | ($pri | tonumber) as $pn
            | (if   $pn <= 3 then "err"
               elif $pn == 4 then "warning"
               else "info" end) as $sev
            | [
                ((.__REALTIME_TIMESTAMP // "0") | tonumber / 1000000 | strftime("%Y-%m-%dT%H:%M:%S+00:00")),
                (._SYSTEMD_UNIT // .SYSLOG_IDENTIFIER // "_"),
                $sev,
                (.MESSAGE // "")
              ]
            | @tsv
        ' \
        | mask \
        | awk -F'\t' '{ printf "%s %s %s %s\n", $1, $2, $3, $4 }'
fi

# ---------- 2. 추가 파일 (선택) ---------------------------------------------
if [[ -n "$EXTRA" ]]; then
    IFS=',' read -ra FILES <<< "$EXTRA"
    for f in "${FILES[@]}"; do
        [[ -r "$f" ]] || continue
        # 추가 파일은 형식을 모르므로 unit=<file-basename> severity=info 로 단순 wrap
        bn="$(basename "$f")"
        ts="$(date -u '+%Y-%m-%dT%H:%M:%S+00:00')"
        # 큰 파일은 마지막 5000줄만
        tail -n 5000 "$f" \
            | mask \
            | awk -v ts="$ts" -v bn="$bn" '{print ts" "bn" info "$0}'
    done
fi

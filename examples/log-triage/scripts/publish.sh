#!/usr/bin/env bash
# USAGE: bash scripts/publish.sh <output.json>
#
# Claude 가 생성한 트리아지 결과 JSON 을 채널에 발행한다.
# severity=error 가 있으면 즉시 알림, 아니면 다이제스트 (severity=warning 만 모음).
#
# 환경변수:
#   LOG_TRIAGE_PUBLISH    ntfy | slack | issue | stdout (기본: stdout)
#   LOG_TRIAGE_STATE_DIR  상태 디렉토리 (기본: /var/lib/log-triage)
#   NTFY_TOPIC            publish=ntfy 일 때 필수
#   NTFY_SERVER           기본 https://ntfy.sh
#   SLACK_WEBHOOK_URL     publish=slack 일 때 필수
#   GITHUB_REPO           publish=issue 일 때 필수
#   LOG_TRIAGE_SUPPRESS_INFO  1 이면 info-only 결과는 발행 생략

set -euo pipefail

JSON_PATH="${1:?usage: publish.sh <output.json>}"
[[ -s "$JSON_PATH" ]] || { echo "input json empty"; exit 1; }

CHANNEL="${LOG_TRIAGE_PUBLISH:-stdout}"
STATE_DIR="${LOG_TRIAGE_STATE_DIR:-/var/lib/log-triage}"
mkdir -p "$STATE_DIR"

SUMMARY="$(jq -r .summary "$JSON_PATH")"
HAS_ERROR="$(jq '[.issues[]? | select(.severity == "error")] | length' "$JSON_PATH")"
HAS_WARN="$(jq  '[.issues[]? | select(.severity == "warning")] | length' "$JSON_PATH")"

# info 만 있으면 시끄럽지 않게 생략 옵션
if [[ "${LOG_TRIAGE_SUPPRESS_INFO:-1}" == "1" ]] \
   && (( HAS_ERROR == 0 )) && (( HAS_WARN == 0 )); then
    echo "info-only — 발행 생략" >&2
    touch /tmp/log-triage-work/published.flag
    exit 0
fi

# severity 별 컬러/제목
if (( HAS_ERROR > 0 )); then
    PRIORITY="urgent"
    TITLE="🔴 [log-triage] error ${HAS_ERROR}건"
elif (( HAS_WARN > 0 )); then
    PRIORITY="default"
    TITLE="🟡 [log-triage] warning ${HAS_WARN}건"
else
    PRIORITY="low"
    TITLE="🟢 [log-triage] 정상"
fi

# 사람 친화 본문 — issues 를 짧게 나열
BODY="$(jq -r '
    .summary as $s |
    "[" + (.window // "?") + "] " + $s + "\n\n" +
    ((.issues // []) | map(
        "• [" + .severity + "/" + (.count|tostring) + "] " +
        (.unit // "_") + " — " + .pattern +
        (if .is_new then "  (NEW)" else "" end) +
        "\n  ↳ " + .suggested_action
    ) | join("\n"))
' "$JSON_PATH")"

case "$CHANNEL" in
    stdout)
        printf '%s\n%s\n' "$TITLE" "$BODY"
        ;;
    ntfy)
        : "${NTFY_TOPIC:?NTFY_TOPIC 미설정}"
        SERVER="${NTFY_SERVER:-https://ntfy.sh}"
        curl -fsS \
            -H "Title: $TITLE" \
            -H "Priority: $PRIORITY" \
            -H "Tags: triage,$(if (( HAS_ERROR > 0 )); then echo error; else echo warning; fi)" \
            -d "$BODY" \
            "$SERVER/$NTFY_TOPIC" >/dev/null
        ;;
    slack)
        : "${SLACK_WEBHOOK_URL:?SLACK_WEBHOOK_URL 미설정}"
        # Slack 은 JSON 본문 + ```fenced``` 으로 가독성
        PAYLOAD="$(jq -n \
            --arg t "$TITLE" \
            --arg b "$BODY" \
            '{text: ($t + "\n```\n" + $b + "\n```")}')"
        curl -fsS -H 'Content-Type: application/json' \
            -d "$PAYLOAD" "$SLACK_WEBHOOK_URL" >/dev/null
        ;;
    issue)
        : "${GITHUB_REPO:?GITHUB_REPO 미설정}"
        command -v gh >/dev/null 2>&1 || { echo "gh CLI 없음"; exit 1; }
        # severity=error 일 때만 이슈 생성, 나머지는 stdout
        if (( HAS_ERROR > 0 )); then
            gh issue create \
                --repo "$GITHUB_REPO" \
                --title "$TITLE" \
                --body  "$BODY" \
                --label "log-triage,severity:error" >/dev/null
        else
            printf '%s\n%s\n' "$TITLE" "$BODY"
        fi
        ;;
    *)
        echo "알 수 없는 LOG_TRIAGE_PUBLISH=$CHANNEL"; exit 1
        ;;
esac

# ---------- 새 패턴 캐시 갱신 -----------------------------------------------
SEEN="$STATE_DIR/seen-patterns.json"
[[ -s "$SEEN" ]] || echo '{"patterns":[]}' > "$SEEN"

# 입력 JSON 의 모든 pattern → SHA-256 → 캐시에 union, 최근 1000개만 유지
NEW_HASHES="$(jq -r '.issues[]?.pattern' "$JSON_PATH" \
    | while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        printf 'sha256:%s\n' "$(printf '%s' "$p" | sha256sum | awk '{print $1}')"
      done)"

if [[ -n "$NEW_HASHES" ]]; then
    jq --argjson new "$(jq -Rsc 'split("\n") | map(select(length > 0))' <<< "$NEW_HASHES")" \
        '.patterns = ((.patterns + $new) | unique | .[-1000:])' \
        "$SEEN" > "$SEEN.tmp" && mv "$SEEN.tmp" "$SEEN"
fi

touch /tmp/log-triage-work/published.flag

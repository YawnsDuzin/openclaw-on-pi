#!/usr/bin/env bash
# USAGE: bash scripts/pick-issue.sh
#
# `automation:cleanup` 라벨이 붙은 열린 이슈 중 1건을 골라
# /tmp/pr-bot-state/picked-issue.json 에 기록한다.
#
# 락 파일로 중복 선택을 방지한다.
#
# 환경변수:
#   PR_BOT_REPO          (필수) 대상 저장소
#   PR_BOT_LABEL         (선택) 트리거 라벨, 기본 automation:cleanup
#   PR_BOT_BRANCH_PREFIX (선택) 브랜치 prefix, 기본 bot/auto
#   PR_BOT_STATE_DIR     (선택) 상태/락 디렉토리, 기본 /tmp/pr-bot-state
#   PR_BOT_LOCK_TTL      (선택) 락 TTL 초, 기본 7200 (2시간)

set -euo pipefail

REPO="${PR_BOT_REPO:?PR_BOT_REPO 미설정}"
LABEL="${PR_BOT_LABEL:-automation:cleanup}"
PREFIX="${PR_BOT_BRANCH_PREFIX:-bot/auto}"
STATE_DIR="${PR_BOT_STATE_DIR:-/tmp/pr-bot-state}"
LOCK_TTL="${PR_BOT_LOCK_TTL:-7200}"

mkdir -p "$STATE_DIR"
LOCK="$STATE_DIR/lock"
LOG_PREFIX="[pick-issue]"
log() { printf '%s %s\n' "$LOG_PREFIX" "$*" >&2; }

# 락 만료 확인 — 죽은 락은 자동 회수
if [[ -f "$LOCK" ]]; then
    age=$(( $(date +%s) - $(stat -c '%Y' "$LOCK" 2>/dev/null || stat -f '%m' "$LOCK") ))
    if (( age < LOCK_TTL )); then
        log "락 활성 (age=${age}s, TTL=${LOCK_TTL}s) — 다른 인스턴스 작업 중. 종료."
        exit 0
    fi
    log "락 만료 (age=${age}s) — 회수"
    rm -f "$LOCK"
fi

command -v gh >/dev/null 2>&1 || { log "gh CLI 없음"; exit 1; }
command -v jq >/dev/null 2>&1 || { log "jq 없음";    exit 1; }

# 직전 작업한 이슈 번호 캐시 (반복 방지)
RECENT="$STATE_DIR/recent-issues.txt"
touch "$RECENT"

# 이슈 후보 조회 — 최근 처리한 N개 제외, 가장 오래된 것 우선
log "라벨 '$LABEL' 의 열린 이슈 조회 (repo=$REPO)..."
candidates="$(gh issue list \
    --repo "$REPO" \
    --label "$LABEL" \
    --state open \
    --limit 20 \
    --json number,title,body,createdAt,labels \
    --jq 'sort_by(.createdAt) | .[]')"

if [[ -z "$candidates" ]]; then
    log "후보 이슈 없음. 종료."
    exit 0
fi

picked=""
while IFS= read -r issue; do
    num="$(jq -r .number <<< "$issue")"
    if grep -qx "$num" "$RECENT"; then
        log "이슈 #$num 최근 처리됨 — skip"
        continue
    fi
    picked="$issue"
    break
done < <(jq -c '.' <<< "$candidates")

if [[ -z "$picked" ]]; then
    log "처리 가능한 이슈 없음 (모두 최근 처리됨). 종료."
    exit 0
fi

NUM="$(jq -r .number <<< "$picked")"
TITLE="$(jq -r .title <<< "$picked")"
BRANCH="${PREFIX}/${NUM}"

# 결과 기록
jq -n \
    --argjson num "$NUM" \
    --arg title "$TITLE" \
    --arg body  "$(jq -r .body <<< "$picked")" \
    --arg branch "$BRANCH" \
    '{number: $num, title: $title, body: $body, branch: $branch}' \
    > "$STATE_DIR/picked-issue.json"

# 락 + 최근 처리 기록
date +%s > "$LOCK"
echo "$NUM" >> "$RECENT"
# recent 파일은 최근 50개만 유지
tail -n 50 "$RECENT" > "$RECENT.tmp" && mv "$RECENT.tmp" "$RECENT"

log "선택: #$NUM '$TITLE' → branch '$BRANCH'"
log "결과 파일: $STATE_DIR/picked-issue.json"

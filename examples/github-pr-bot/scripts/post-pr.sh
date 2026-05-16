#!/usr/bin/env bash
# USAGE: bash scripts/post-pr.sh <issue-number> <branch>
#
# 푸시된 브랜치로 PR 을 생성하고 라벨링 + 본문 보강.
#
# 환경변수:
#   PR_BOT_REPO        (필수) 대상 저장소
#   PR_BOT_LABEL_AUTO  자동 부여할 PR 라벨 (기본: bot:auto)
#   PR_BOT_DRY_RUN     1 이면 PR 만들지 않고 stdout 에 본문만 출력
#   PR_BOT_STATE_DIR   상태 디렉토리 (기본 /tmp/pr-bot-state)

set -euo pipefail

NUM="${1:?issue-number 인자 누락}"
BRANCH="${2:?branch 인자 누락}"

REPO="${PR_BOT_REPO:?PR_BOT_REPO 미설정}"
LABEL_AUTO="${PR_BOT_LABEL_AUTO:-bot:auto}"
DRY_RUN="${PR_BOT_DRY_RUN:-0}"
STATE_DIR="${PR_BOT_STATE_DIR:-/tmp/pr-bot-state}"

LOG_PREFIX="[post-pr]"
log() { printf '%s %s\n' "$LOG_PREFIX" "$*" >&2; }

command -v gh >/dev/null 2>&1 || { log "gh CLI 없음"; exit 1; }

ISSUE_JSON="$STATE_DIR/picked-issue.json"
[[ -f "$ISSUE_JSON" ]] || { log "$ISSUE_JSON 없음 — pick-issue.sh 먼저"; exit 1; }

TITLE="$(jq -r .title "$ISSUE_JSON")"

# 변경 통계
LINES_CHANGED="$(git diff --shortstat "${BRANCH}~1..${BRANCH}" 2>/dev/null \
    | grep -oE '[0-9]+ insertion|[0-9]+ deletion' \
    | grep -oE '[0-9]+' \
    | awk '{s+=$1} END {print s+0}')"

# 본문 — 매우 단순한 redaction (이메일/IP/Bearer)
BODY=$(cat <<EOF
Closes #${NUM}

자동 생성된 정리 PR.

- 이슈: **${TITLE}**
- 변경 라인 수: ${LINES_CHANGED}
- 트리거: \`automation:cleanup\` 라벨
- 봇: github-pr-bot (openclaw-on-pi)

> 사람 1명 승인 필수. 머지 전 변경 내용 반드시 검토.
EOF
)

# 매우 단순한 redaction — 필요 시 detect-secrets 등으로 강화
BODY="$(printf '%s\n' "$BODY" \
    | sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/<email>/g' \
    | sed -E 's/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/<ip>/g' \
    | sed -E 's/Bearer [A-Za-z0-9._\-]+/Bearer <token>/g')"

if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY-RUN: PR 생성 안 함. 본문 ↓"
    printf '%s\n' "$BODY"
    exit 0
fi

log "PR 생성 (repo=$REPO, head=$BRANCH)..."
PR_URL="$(gh pr create \
    --repo "$REPO" \
    --head "$BRANCH" \
    --base "$(gh repo view "$REPO" --json defaultBranchRef --jq .defaultBranchRef.name)" \
    --title "$TITLE" \
    --body  "$BODY" \
    --label "$LABEL_AUTO" 2>&1 | tail -1)"

if [[ ! "$PR_URL" =~ ^https://github\.com/ ]]; then
    log "PR 생성 실패: $PR_URL"
    exit 1
fi

echo "$PR_URL" > "$STATE_DIR/last-pr.txt"
log "PR 생성 완료: $PR_URL"

# 락 해제 (다음 사이클에서 다른 이슈 처리 가능)
rm -f "$STATE_DIR/lock"

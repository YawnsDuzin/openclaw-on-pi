---
name: cleanup-issue
description: GitHub 저장소의 'automation:cleanup' 라벨이 붙은 열린 이슈를 1건 골라 작은 변경 PR (≤30 라인) 을 자동 생성한다. 사용자가 '/cleanup-issue' 슬래시 명령으로 직접 트리거하거나, cron 으로 6시간마다 자동 실행한다. main 직접 푸시 금지, 새 브랜치 + 사람 승인 필수.
user-invocable: true
metadata:
  openclaw:
    requires:
      env:
        - PR_BOT_REPO
        - GITHUB_TOKEN
      bins:
        - gh
        - git
        - jq
---

# cleanup-issue (skill)

> ⚠ **상태: 코드 작성 완료, 실 저장소 검증 X**
> 첫 가동 시 반드시 `PR_BOT_DRY_RUN=1` 로 1주일 그림자 가동 후 활성화.

## 의도

라벨 `automation:cleanup` 이 붙은 열린 이슈 1건을 골라 (가장 오래된 것 우선, 최근 처리한 건 제외) → 새 브랜치 → 작은 변경 (≤30 라인) → PR 생성 → `bot:auto` 라벨. **main 직접 푸시는 절대 금지** — 항상 새 브랜치 + 사람 승인 강제.

## 트리거

- **슬래시 명령**: 페어링된 사용자가 채널에서 `/cleanup-issue` → 즉시 1회 실행
- **Cron**: `~/.openclaw/openclaw.json` 의 `cron.jobs` 에 `0 */6 * * *` 로 등록 시 6시간마다 자동
- **수동**: `bash scripts/pick-issue.sh && openclaw agent --skill cleanup-issue` (테스트용)

## 환경변수

| 변수 | 의미 | 기본값 |
|---|---|---|
| `PR_BOT_REPO` | 대상 저장소 (`user/repo`) | **(필수)** |
| `GITHUB_TOKEN` | fine-grained PAT (`contents:write`, `pull_requests:write`, `metadata:read`) | **(필수)** |
| `PR_BOT_LABEL` | 트리거 라벨 | `automation:cleanup` |
| `PR_BOT_BRANCH_PREFIX` | 새 브랜치 prefix | `bot/auto` |
| `PR_BOT_LABEL_AUTO` | 봇 PR 라벨 | `bot:auto` |
| `PR_BOT_STATE_DIR` | 상태/락 디렉토리 | `/tmp/pr-bot-state` |
| `PR_BOT_LOCK_TTL` | 락 TTL (초) | `7200` (2h) |
| `PR_BOT_DRY_RUN` | `1` 이면 PR 만들지 않음 | `0` |

env 보관: `~/.openclaw-secrets/github.env` (권한 600) → systemd `EnvironmentFile=-...` 로 주입.

## 실행 절차

1. **이슈 선택** — `scripts/pick-issue.sh` 실행. 출력: `/tmp/pr-bot-state/picked-issue.json` (`number, title, body, branch`). 후보 없으면 종료 코드 0 으로 빠져나옴 (정상).

2. **이슈 본문 검토** — JSON 의 `body` 가 모호하거나 비어 있으면 **종료 코드 2** (요청자가 본문 보강 후 재트리거). 추측 금지.

3. **브랜치 생성**:

   ```bash
   git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH"
   ```

4. **변경 적용** — 이슈 본문이 요구하는 작은 변경 (오타 / 변수명 / lint 경고 1건 / 안 쓰이는 import 정리 등).

5. **변경 라인 검증** — 적용 후:

   ```bash
   LINES="$(git diff --shortstat | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')"
   [[ "$LINES" -gt 0  ]] || exit 2   # 변경 없으면 PR 만들지 않음
   [[ "$LINES" -le 30 ]] || exit 2   # 너무 크면 사람에게 위임
   ```

6. **커밋 + 푸시**:

   ```bash
   git add -A
   git commit -m "fix(#${NUM}): <짧은 요약>"
   git push origin "$BRANCH"
   ```

7. **PR 생성** — `bash scripts/post-pr.sh <NUM> <BRANCH>`. 본문에 `Closes #<NUM>` + 변경 통계 + 출처 표시. `PR_BOT_DRY_RUN=1` 이면 본문만 stdout.

## 절대 규칙

- **변경 라인 ≤ 30** — 큰 작업으로 보이면 즉시 종료 코드 2
- **금지 경로**: `.github/`, `scripts/`, `*.lock`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`
- **금지 동작**: 의존성 추가/제거, 외부 네트워크 호출 (`curl`, `wget`), force push, main 직접 푸시
- **PR 본문**: 반드시 `Closes #<num>` 포함. `post-pr.sh` 가 이메일/IP/Bearer 토큰 redaction 패스 적용
- **추측 금지**: 이슈 본문이 모호하면 종료 코드 2
- **테스트 깨지면 되돌리기**: `git checkout .` 후 종료 코드 1

## 커밋 / 브랜치 형식

- 커밋: `fix(#<issue-number>): <한 줄 요약>`
- 브랜치: `${PR_BOT_BRANCH_PREFIX:-bot/auto}/<issue-number>`

## 안전장치

| 위험 | 대응 |
|---|---|
| 같은 이슈 무한 처리 | `scripts/pick-issue.sh` 의 `recent-issues.txt` 캐시 + 락 TTL |
| 두 인스턴스 동시 실행 | `pick-issue.sh` 의 `lock` 파일 + TTL |
| main 직접 푸시 | 본 SKILL.md 의 절대 규칙 + GitHub 브랜치 보호 규칙 (외부 설정) |
| force push | 마찬가지 — 본 스킬 자체가 사용 안 함 |
| 큰 변경 폭주 | 위 §5 의 ≤30 라인 가드 |
| 의존성 임의 추가 | 위 절대 규칙 |
| 본문 민감정보 노출 | `post-pr.sh` 의 redaction (이메일/IP/Bearer). 부족하면 `detect-secrets` 추가 |
| PR 자동 머지 위험 | GitHub 브랜치 보호로 사람 승인 1명 강제 (외부 설정) |

## 검증 (스킬 종료 후 OpenClaw 가 확인)

- `$PR_BOT_DRY_RUN == "1"` 이면 검증 스킵 (stdout 에 본문만)
- 아니면 `/tmp/pr-bot-state/last-pr.txt` 가 `https://github.com/.+/pull/[0-9]+$` 패턴인지

검증 실패 시 OpenClaw 의 dead-letter / 알람으로 보내고 **자동 재시도 금지** (같은 이슈 무한 루프 방지).

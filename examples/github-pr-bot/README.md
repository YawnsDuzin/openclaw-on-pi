# Example — github-pr-bot

> GitHub 이슈를 읽고 작은 변경 PR 을 자동 생성하는 봇 예제.

⚠ **상태: 코드 작성 완료, 실 저장소 검증 X**
정적 리뷰만 통과한 best-effort 구현. 첫 사용 전 반드시 `PR_BOT_DRY_RUN=1` 로 1주일 그림자 가동(production-shadow) 후 활성화.

---

## 의도

- 라벨 `automation:cleanup` 이 붙은 열린 이슈를 폴링
- 가장 오래된 1건을 골라 (최근 처리한 건 제외):
  - 새 브랜치 `bot/auto/<issue-number>` 생성
  - 변경 적용 (Claude Code 가 수행) — **변경 라인 ≤ 30**
  - 커밋 + 푸시 + PR 생성 + `bot:auto` 라벨
  - PR 본문에 `Closes #<num>`
- **main 직접 푸시 절대 금지**

---

## 디렉토리 구조

```
github-pr-bot/
├── README.md
├── tasks.yaml             ← OpenClaw task: pre/prompt/verify/on_failure
├── CLAUDE.md              ← 봇 행동 규칙
├── settings.example.json  ← gh CLI / git push 권한 화이트리스트
└── scripts/
    ├── pick-issue.sh      ← 이슈 1건 선택, 락 + 최근 처리 캐시
    └── post-pr.sh         ← PR 생성 + 라벨링 + 본문 redaction
```

---

## 필요 환경

- `gh` CLI 설치 + 인증
  ```bash
  # PAT 안전 보관 (권한 600)
  mkdir -p ~/.openclaw-secrets && chmod 700 ~/.openclaw-secrets
  echo "GITHUB_TOKEN=ghp_xxx" > ~/.openclaw-secrets/github.env
  chmod 600 ~/.openclaw-secrets/github.env

  # gh 인증
  source ~/.openclaw-secrets/github.env
  echo "$GITHUB_TOKEN" | gh auth login --with-token
  ```

- fine-grained PAT 스코프: `contents:write`, `pull_requests:write`, `metadata:read`
- 대상 저장소에 라벨 사전 생성: `automation:cleanup`, `bot:auto`
- 브랜치 보호 규칙: PR 머지에 사람 승인 1명 필수 (이건 봇이 못 만지는 외부 설정)

---

## 환경변수

| 변수 | 의미 | 기본값 |
|---|---|---|
| `PR_BOT_REPO` | 대상 저장소 (`user/repo`) | **(필수)** |
| `PR_BOT_LABEL` | 트리거 라벨 | `automation:cleanup` |
| `PR_BOT_BRANCH_PREFIX` | 새 브랜치 prefix | `bot/auto` |
| `PR_BOT_LABEL_AUTO` | 봇 PR 라벨 | `bot:auto` |
| `PR_BOT_STATE_DIR` | 상태/락 디렉토리 | `/tmp/pr-bot-state` |
| `PR_BOT_LOCK_TTL` | 락 TTL (초) | `7200` (2h) |
| `PR_BOT_DRY_RUN` | `1` 이면 PR 만들지 않음 | `0` |

---

## 사용법

### 1) 권한 화이트리스트 적용

```bash
cp examples/github-pr-bot/settings.example.json ~/.claude/settings.json
# 또는 기존 settings 와 머지
```

### 2) 첫 가동 — DRY-RUN

```bash
export PR_BOT_REPO=youruser/yourrepo
export PR_BOT_DRY_RUN=1

openclaw enqueue --task cleanup-issue \
    --tasks-file examples/github-pr-bot/tasks.yaml
openclaw run --once --log-level debug
```

기대:

- `pick-issue.sh` 가 후보 이슈 1건 선택 → `/tmp/pr-bot-state/picked-issue.json`
- Claude Code 가 변경 시도
- `post-pr.sh` 가 PR **본문만 stdout 에 출력** (실제 PR 생성 X)

이 단계에서 본문이 적절한지 / 변경 라인이 30 이하인지 / 금지 경로를 안 건드렸는지 사람이 검토.

### 3) 활성 가동

```bash
unset PR_BOT_DRY_RUN
# systemd timer 로 cron-like (recipes/scheduled-agent-tasks 참고)
```

---

## 안전장치 정리

| 위험 | 대응 |
|---|---|
| 같은 이슈 무한 처리 | `recent-issues.txt` 캐시 + `on_failure.requeue: false` |
| 두 인스턴스 동시 실행 | `pick-issue.sh` 의 `lock` 파일 + TTL |
| main 직접 푸시 | `settings.example.json` 의 `Bash(git push origin main:*)` deny |
| force push | 같은 deny 리스트 |
| 큰 변경 폭주 | `verify` 블록 + CLAUDE.md 의 "변경 라인 ≤ 30" |
| 의존성 임의 추가 | `Bash(npm install:*)`, `Bash(pip install:*)` deny + `Edit(**/*.lock)` deny |
| 본문 민감정보 노출 | `post-pr.sh` 의 redaction (이메일/IP/Bearer) — 미흡하면 `detect-secrets` 추가 |
| PR 자동 머지 위험 | 브랜치 보호로 사람 승인 강제 (외부 설정) |

---

## 검증 후 할 일

`PR_BOT_DRY_RUN=1` 로 1주일 그림자 가동 → 본문 / 변경 패턴 검토 → 활성화. 이후:

- 본 README 의 ⚠ → ✅
- 루트 README 의 examples 표 마커도 갱신
- 실패 케이스가 있으면 [troubleshooting](../../docs/troubleshooting.md) 에 추가

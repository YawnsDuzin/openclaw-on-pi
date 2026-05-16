# Example — github-pr-bot

> GitHub 이슈를 작은 변경 PR 로 자동 변환하는 OpenClaw 스킬.

⚠ **상태: 코드 작성 완료, 실 저장소 검증 X**
정적 리뷰만 통과한 best-effort 구현. 첫 사용 전 반드시 `PR_BOT_DRY_RUN=1` 로 1주일 그림자 가동(production-shadow) 후 활성화.

> 📜 2026-05-16 재작성 라운드 — 1차 라운드의 `tasks.yaml` / `openclaw enqueue` 가상 스키마는 OpenClaw 의 실제 인터페이스가 아니어서 폐기. 본 라운드는 SKILL.md + bundled scripts 패턴.

---

## 의도

- 라벨 `automation:cleanup` 이 붙은 열린 이슈 1건을 처리
- 작은 변경 (`≤30 라인`) → 새 브랜치 → 커밋 → PR + `bot:auto` 라벨
- **main 직접 푸시 금지**, 머지에 사람 승인 1명 필수

---

## 디렉토리 구조

```
github-pr-bot/
├── README.md
├── SKILL.md                    ← 스킬 정의 (frontmatter + 본문 + 절대 규칙)
└── scripts/
    ├── pick-issue.sh           ← 이슈 1건 선택, 락 + 최근 처리 캐시
    └── post-pr.sh              ← PR 생성 + 라벨링 + 본문 redaction
```

---

## 필요 환경

- `gh` CLI 설치 + 인증
- fine-grained PAT 스코프: `contents:write`, `pull_requests:write`, `metadata:read`
- 대상 저장소에 라벨 사전 생성: `automation:cleanup`, `bot:auto`
- 대상 저장소의 브랜치 보호 규칙: PR 머지에 사람 승인 1명 필수 (이건 봇이 못 만지는 외부 설정)

PAT 안전 보관:

```bash
mkdir -p ~/.openclaw-secrets && chmod 700 ~/.openclaw-secrets
cat > ~/.openclaw-secrets/github.env <<'EOF'
GITHUB_TOKEN=ghp_xxx
PR_BOT_REPO=youruser/yourrepo
EOF
chmod 600 ~/.openclaw-secrets/github.env

# gh 인증 (1회)
source ~/.openclaw-secrets/github.env
echo "$GITHUB_TOKEN" | gh auth login --with-token
```

---

## 설치 — 본 스킬을 OpenClaw 에 등록

```bash
# 1) 본 디렉토리를 ~/.openclaw/skills/cleanup-issue 로 복사
DEST="$HOME/.openclaw/skills/cleanup-issue"
mkdir -p "$DEST/scripts"
cp examples/github-pr-bot/SKILL.md            "$DEST/SKILL.md"
cp examples/github-pr-bot/scripts/*.sh        "$DEST/scripts/"
chmod +x "$DEST/scripts/"*.sh

# 2) OpenClaw 가 새 스킬을 인식하는지 확인 (재기동 또는 reload)
systemctl --user restart openclaw    # 또는: openclaw reload
openclaw skills list | grep cleanup-issue
```

---

## 사용법

### 1) DRY-RUN — 1주일 그림자 가동

`~/.openclaw-secrets/github.env` 에 `PR_BOT_DRY_RUN=1` 추가 후:

```bash
# Telegram 채널에서 페어링된 사용자가 입력
/cleanup-issue

# 또는 셸에서 수동
source ~/.openclaw-secrets/github.env
openclaw agent --skill cleanup-issue
```

기대:

- `pick-issue.sh` 가 후보 이슈 1건 선택 → `/tmp/pr-bot-state/picked-issue.json`
- 모델이 변경 시도
- `post-pr.sh` 가 **PR 본문만 stdout 에 출력** (실제 PR 생성 X)

이 단계에서 본문이 적절한지 / 변경 라인이 30 이하인지 / 금지 경로를 안 건드렸는지 사람이 검토.

### 2) 활성 가동

`PR_BOT_DRY_RUN=1` 제거 + cron 등록 (선택):

```json5
// ~/.openclaw/openclaw.json 의 cron 절
{
  cron: {
    enabled: true,
    jobs: [
      {
        schedule: "0 */6 * * *",
        skill: "cleanup-issue",
      },
    ],
  },
}
```

---

## 안전장치 정리

| 위험 | 대응 |
|---|---|
| 같은 이슈 무한 처리 | `pick-issue.sh` 의 `recent-issues.txt` 캐시 + 락 TTL |
| 두 인스턴스 동시 실행 | `pick-issue.sh` 의 `lock` 파일 (2h TTL) |
| main 직접 푸시 | SKILL.md 의 절대 규칙 + 대상 저장소의 브랜치 보호 |
| 큰 변경 폭주 | SKILL.md §5 의 `LINES ≤ 30` 가드 |
| 본문 민감정보 노출 | `post-pr.sh` redaction (이메일/IP/Bearer). 미흡하면 `detect-secrets` 추가 |
| 추측 PR | 이슈 본문 모호 → 종료 코드 2 (재트리거 안 됨) |
| PR 자동 머지 | 대상 저장소 브랜치 보호로 사람 승인 1명 (외부) |
| Prompt Injection | 이슈 본문에 숨긴 지시문 위험 — [docs/07 §6](../../docs/07-openclaw-hardening.md#6-prompt-injection-운영-완화) 운영 완화 참고 |

---

## 검증 후 할 일

`PR_BOT_DRY_RUN=1` 로 1주일 그림자 가동 → 본문 / 변경 패턴 검토 → 활성화. 이후:

- 본 README 의 ⚠ → ✅
- 루트 README 의 examples 표 마커도 갱신
- 실패 케이스가 있으면 [troubleshooting](../../docs/troubleshooting.md) 에 추가

---

## 흔한 실패 케이스

| 증상 | 원인 / 해결 |
|---|---|
| `pick-issue.sh: 락 활성` | 다른 인스턴스가 작업 중. 2시간 대기 또는 `/tmp/pr-bot-state/lock` 확인 |
| `gh: command not found` | `bootstrap-pi.sh` 가 깐 apt 패키지에 `gh` 미포함. `sudo apt-get install gh` |
| 변경 라인 0 | 이슈 본문이 명확하지 않거나 모델이 변경할 곳을 못 찾음 → 본문 보강 후 재트리거 |
| 401 / `gh auth status` 실패 | PAT 만료. `~/.openclaw-secrets/github.env` 갱신 후 `gh auth login --with-token` |
| PR 본문에 토큰 누출 | `post-pr.sh` 의 redaction 미흡 — `detect-secrets` 같은 도구로 보강 |

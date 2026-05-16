# Recipe — 자율 코딩 루프 24/7

> Pi 가 깨어 있는 동안 정기적으로 GitHub 저장소를 살펴보고 작은 개선 PR 을 자동으로 만든다.

⚠ 검증 환경: 단일 저장소 + OpenClaw ≥ 2026.2.6 + Anthropic Sonnet (BYOK) + 작업당 평균 5–10분.

> 📜 2026-05-16 재작성 라운드 — 본 레시피는 [`examples/github-pr-bot`](../examples/github-pr-bot/) 의 `cleanup-issue` 스킬을 cron 으로 자동화하는 패턴.

---

## 시나리오

- 본인 사이드 프로젝트 1–3개를 등록
- Pi 가 매 6시간마다 한 번씩:
  - 닫힌 이슈 라벨 `automation:cleanup` 에 해당하는 작은 정리 작업 1건
  - 변경 라인 ≤ 30 가드 + 새 브랜치 + PR
  - main 직접 푸시 절대 금지

---

## 필요 조건

- [03 — OpenClaw 설치](../docs/03-openclaw-install.md) 완료 + `openclaw onboard` 끝
- [`examples/github-pr-bot`](../examples/github-pr-bot/) 의 `cleanup-issue` 스킬을 `~/.openclaw/skills/` 에 설치 + 1주일 DRY-RUN 그림자 가동 통과
- GitHub fine-grained PAT (`contents:write`, `pull_requests:write`, `metadata:read`) — `~/.openclaw-secrets/github.env` 에 보관, 600 권한
- 대상 저장소에 `automation:cleanup` 라벨 + 브랜치 보호 규칙 (사람 승인 1명)

---

## 단계

### 1) 스킬 설치 (이미 했다면 스킵)

```bash
DEST="$HOME/.openclaw/skills/cleanup-issue"
mkdir -p "$DEST/scripts"
cp examples/github-pr-bot/SKILL.md     "$DEST/SKILL.md"
cp examples/github-pr-bot/scripts/*.sh "$DEST/scripts/"
chmod +x "$DEST/scripts/"*.sh

systemctl --user restart openclaw
openclaw skills list | grep cleanup-issue
```

### 2) cron 등록 — OpenClaw 내장 `cron.jobs`

`~/.openclaw/openclaw.json` 의 `cron` 키:

```json5
{
  cron: {
    enabled: true,
    jobs: [
      {
        schedule: "0 */6 * * *",       // 6시간마다
        skill: "cleanup-issue",
        env: {
          // ~/.openclaw-secrets/github.env 가 systemd EnvironmentFile 로 주입되면 생략 가능
          PR_BOT_REPO: "youruser/yourrepo",
        },
      },
    ],
  },
}
```

`openclaw config validate` 로 문법 점검 후 daemon 재기동.

### 3) 첫 실행 — 수동 트리거로 검증

```bash
source ~/.openclaw-secrets/github.env
openclaw agent --skill cleanup-issue
```

기대:

- `gh pr list --repo "$PR_BOT_REPO" --label bot:auto` 에 PR 1개
- 변경 라인 ≤ 30
- 본문에 `Closes #<num>`

### 4) 알림 — Telegram 으로 결과 보고 (선택)

스킬 종료 후 Telegram 채널에 한 줄 회신:

```bash
# ~/.openclaw/skills/cleanup-issue/scripts/post-pr.sh 끝에 한 줄 추가
openclaw message send --target tg:000000000 --message "PR 생성: $PR_URL"
```

---

## 운영 팁

- **일일 할당량 제한**: cron schedule 을 `0 */6 * * *` → 하루 4회로 시작. 안정화 후 늘리기
- **PR 라벨**: 자동 PR 에 `bot:auto` (post-pr.sh 가 자동 부여). 사람 PR 과 분리
- **리뷰 의무화**: GitHub 브랜치 보호 규칙으로 사람 승인 1명 필수 — 자동 머지 금지 (OpenClaw 가 못 만지는 외부 설정)
- **dry-run 시간대**: 첫 1주는 `PR_BOT_DRY_RUN=1` 로 PR 만들지 않고 본문만 stdout 으로

---

## 알려진 한계

- **컨텍스트 폭발**: 큰 저장소를 매 호출마다 풀 스캔하면 토큰 한도 hit. SKILL.md 에 "관심 디렉토리만 보기" 절대 규칙 추가
- **이슈 선택의 반복성**: `pick-issue.sh` 의 `recent-issues.txt` 캐시로 같은 이슈 재시도 방지
- **레이트 리밋**: BYOK provider 한도. 멀티 잡 + 짧은 간격은 빠르게 throttle
- **Prompt Injection**: 이슈 본문에 숨긴 지시문으로 모델이 다른 동작을 할 수 있음 — [`docs/07 §6`](../docs/07-openclaw-hardening.md#6-prompt-injection-운영-완화)

---

## 다음

- [멀티 에이전트 오케스트레이션](./multi-agent-orchestration.md)
- [cron 기반 스케줄 작업](./scheduled-agent-tasks.md)
- [07 — Hardening](../docs/07-openclaw-hardening.md)

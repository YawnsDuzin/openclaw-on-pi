# Recipe — 자율 코딩 루프 24/7

> Pi 가 깨어 있는 동안 정기적으로 GitHub 저장소를 살펴보고 작은 개선 PR 을 자동으로 만든다.

⚠ 검증 환경: 단일 저장소 + Sonnet 모델 + 작업당 평균 5–10분.

---

## 시나리오

- 본인 사이드 프로젝트 1–3개를 등록
- Pi 가 매 정해진 시각에 다음 중 하나를 시도:
  - 닫힌 이슈 라벨 `automation:cleanup` 에 해당하는 작은 정리 작업
  - dependabot 알림에 대응하는 의존성 bump 검증
  - lint 경고 누적 트리아지
- 결과는 항상 새 브랜치 + PR. main 직접 푸시 금지.

---

## 필요 조건

- [03 — OpenClaw 설치](../docs/03-openclaw-install.md) 완료
- GitHub fine-grained PAT (`contents:write`, `pull_requests:write`) — `~/.openclaw-secrets/github.env` 에 보관, 600 권한
- 대상 저장소에 `automation:cleanup` 같은 트리거 라벨

---

## 단계

### 1) 작업 정의

`/home/dzp/dzp_main/program/openclaw-work/auto-loop/tasks.yaml` (예시 — OpenClaw 의 정확한 스키마는 본 저장소에 적용 시 확인):

```yaml
- name: cleanup-issues
  schedule: "0 */6 * * *"          # 6시간마다
  queue: low
  payload:
    repo: youruser/yourrepo
    label: "automation:cleanup"
    branch_prefix: "bot/auto"
  prompt: |
    아래 저장소의 열린 이슈 중 라벨이 'automation:cleanup' 인 것 하나를
    골라 작은 변경(README 오타, 변수 rename, lint 경고 1건 등) 으로 해결하라.
    새 브랜치 'bot/auto/<issue-number>' 에 커밋하고 PR 생성.
    PR 본문에 'Closes #<num>' 포함.
```

### 2) settings.json 권한

`~/.claude/settings.json` 의 `permissions.allow` 에 다음을 포함:

```json
"Bash(gh issue list:*)",
"Bash(gh issue view:*)",
"Bash(gh pr create:*)",
"Bash(git checkout:*)",
"Bash(git branch:*)",
"Bash(git push:*)"
```

`gh` CLI 가 PAT 로 인증되어 있어야 한다 (`gh auth login --with-token < $GITHUB_TOKEN_FILE`).

### 3) systemd 로 OpenClaw 가동

[05 — Headless Ops](../docs/05-headless-ops.md) 의 systemd 절차 적용. cron 은 OpenClaw 의 내부 schedule 이 처리.

### 4) 첫 실행 검증

수동으로 한 번 트리거:

```bash
openclaw enqueue --task cleanup-issues
openclaw run --once --log-level debug
```

기대:

- `gh pr view` 로 PR 1개 확인
- PR 의 변경 라인 < 30 (작은 작업으로 한정)

---

## 운영 팁

- **일일 할당량 제한**: OpenClaw 의 task 정의에 `daily_max: 4` 같은 키로 폭주 방지. 없으면 외부 카운터 + cron 으로 게이트
- **PR 라벨**: 자동 PR 에 `bot:auto` 라벨을 붙이면 사람 PR 과 구분 / 검색 / 리뷰 자동화 분리 가능
- **리뷰 의무화**: GitHub 브랜치 보호 규칙으로 사람 1명 승인 필수 — 자동 머지 금지
- **dry-run 시간대**: 첫 1주는 `OPENCLAW_DRY_RUN=1` 처럼 PR 만들지 않고 로그만 찍는 모드로 관찰

---

## 알려진 한계

- **컨텍스트 폭발**: 큰 저장소를 매 호출마다 풀 스캔하면 토큰 한도 hit. `CLAUDE.md` 에 "관심 디렉토리만" 명시 + `Glob` 패턴 활용
- **이슈 선택의 반복성**: 같은 이슈를 매번 시도하다가 실패 → 무한 루프. OpenClaw 의 dead-letter 큐 / `--exclude-issue-cache` 적용
- **레이트 리밋**: 구독 플랜 한도. 멀티 큐 + 짧은 간격은 빠르게 throttle

---

## 다음

- [멀티 에이전트 오케스트레이션](./multi-agent-orchestration.md)
- [cron 기반 스케줄 작업](./scheduled-agent-tasks.md)

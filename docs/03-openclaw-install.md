# 03 — OpenClaw 설치

> OpenClaw 자율 에이전트 프레임워크 설치 · 첫 설정 · 첫 작업 실행.

⚠ 검증 환경: 본 문서는 OpenClaw 의 일반적인 설치 모드(pipx / pip / git) 를 추상화한다. 정확한 명령은 OpenClaw 본 저장소의 README 가 우선이며, 본 문서의 절차와 충돌할 경우 본 문서를 갱신하라.

---

## 1. 사전

- [01 — Prerequisites](./01-prerequisites.md) 완료 (Python 3, pip, venv 가 깔려 있어야 함)
- [02 — Claude Code OAuth](./02-claude-code-oauth.md) 인증 완료 (`claude login` 후 `~/.claude/credentials.json` 존재)

---

## 2. 설치

본 저장소의 [`scripts/install-openclaw.sh`](../scripts/install-openclaw.sh) 가 환경에 맞게 분기한다.

```bash
bash scripts/install-openclaw.sh
```

스크립트는 다음 우선순위로 모드를 자동 선택한다:

1. **pipx** (가장 깔끔, 격리된 venv 자동 관리) — `pipx install openclaw`
2. **pip + venv** — `~/.openclaw-venv` 생성 후 `pip install openclaw`, 진입점은 `~/.local/bin/openclaw` 로 심볼릭링크
3. **git clone** — fallback. `~/src/openclaw` 에 클론만 하고 빌드는 OpenClaw README 에 위임

강제 지정:

```bash
OPENCLAW_INSTALL_MODE=pipx bash scripts/install-openclaw.sh
```

설치 확인:

```bash
openclaw --version
which openclaw
```

PATH 에 잡히지 않으면 `~/.bashrc` 에:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

---

## 3. 첫 설정

본 저장소가 제공하는 예제 설정을 복사:

```bash
mkdir -p ~/openclaw-work
cp configs/openclaw.example.yaml ~/openclaw-work/openclaw.yaml
cp configs/CLAUDE.example.md     ~/openclaw-work/CLAUDE.md
```

`~/openclaw-work/openclaw.yaml` 에서 다음을 환경에 맞게 수정:

| 키 | 의미 | 권장값 |
|---|---|---|
| `agent.workdir` | 에이전트 작업 디렉토리 | `~/openclaw-work` |
| `agent.log_level` | 로그 레벨 | 첫 실행 `debug`, 안정화 후 `info` |
| `runtime.claude_code.binary` | claude 바이너리 경로 | `claude` (PATH) |
| `runtime.claude_code.model` | 모델 핀 | `claude-sonnet-4-6` |
| `queues[].max_concurrent` | 동시 실행 | Pi 4 4GB → 1, Pi 5 8GB → 2 |

`CLAUDE.md` 는 Claude Code 가 작업 시작 시 자동 로드하는 컨텍스트다. 본 프로젝트의 컨벤션 / 금지사항을 여기에 적어두면 모든 작업에 일관 적용된다.

---

## 4. 첫 작업 실행 — hello-agent

가장 작은 시나리오: "현재 디렉토리의 README 끝에 한 줄 추가" 같은 무해한 작업으로 파이프라인을 끝에서 끝까지 검증한다.

```bash
mkdir -p ~/openclaw-work/hello && cd ~/openclaw-work/hello
echo "# hello" > README.md
git init -q && git add . && git commit -q -m "init"

# 작업 큐에 task enqueue (OpenClaw CLI 명령은 버전마다 다를 수 있음)
openclaw enqueue \
  --queue default \
  --task "README.md 끝에 'OpenClaw says hi' 한 줄을 추가하고 새 커밋을 만들어라."

# 워커 1회만 실행 (foreground, debug)
openclaw run --once --log-level debug
```

기대:

- Claude Code 가 호출되어 README.md 를 수정
- `git log` 에 새 커밋 1개
- OpenClaw 가 작업 완료 후 큐에서 제거

실패 시 [troubleshooting](./troubleshooting.md) 참고.

---

## 5. 권한 / 안전장치

작업이 의도치 않은 파일을 만지지 않도록 [`configs/claude-code-settings.example.json`](../configs/claude-code-settings.example.json) 의 `permissions.allow` / `deny` 를 적극 활용한다. 핵심:

- **deny 우선**: `Bash(curl:*)`, `Bash(sudo:*)`, `Write(/etc/**)`, `Write(~/.ssh/**)`, `Write(~/.claude/**)`
- **allow 화이트리스트**: 필요한 명령만 노출

자세한 매칭 문법은 [04 — Integration](./04-integration.md) 참고.

---

## 6. 다음 단계

- [04 — Integration](./04-integration.md) — OpenClaw ↔ Claude Code 호출 패턴, 컨텍스트 주입
- [05 — Headless Ops](./05-headless-ops.md) — systemd 로 24/7 가동
- [recipes/auto-coding-loop](../recipes/auto-coding-loop.md) — 자율 코딩 루프

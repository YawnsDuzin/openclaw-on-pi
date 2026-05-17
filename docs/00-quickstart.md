# 00 — Quickstart (처음 사용자 가이드)

> 이 문서 한 페이지로 **빈 Pi → OpenClaw 24/7 가동** 까지 끝낸다.
> 각 단계마다 검증 명령과 실패 시 점프 위치가 명시되어 있다. **위에서 아래로 순서대로** 진행하면 된다.

⚠ 검증 환경: Raspberry Pi 5 (8GB) + Raspberry Pi OS 64-bit Bookworm. Pi 4 (4GB) / Ubuntu Server 24.04 ARM64 호환은 가능하지만 일부 단계가 더 오래 걸릴 수 있다.

> 📌 **Phase 2 (Claude CLI 위임 OAuth) 는 조건부 필수**: OpenClaw 의 인증 모드를 [Claude CLI 위임](./04-integration.md#1-두-인증-모드) 으로 갈 거면 (Claude Pro/Max 구독 활용) Phase 2 필수. API key (BYOK) 모드면 스킵 가능. ([04-integration §1](./04-integration.md#1-두-인증-모드))

---

## 진행 시간 예상

| 구간 | 예상 시간 |
|---|---|
| Phase 1 (사전 점검 + 부트스트랩) | 15–25 분 |
| Phase 2 (Claude CLI + OAuth) — **위임 모드 선택 시** | 5–10 분 |
| Phase 3 (OpenClaw 설치 + onboard + 첫 동작) | 15–25 분 |
| Phase 4 (운영 전환 — systemd) | 5–15 분 |
| **총 (BYOK 모드면 약 35–65 분, 위임 모드면 약 1시간)** | |

이후 (선택): 성능 튜닝 / 레시피 적용 / 추가 예제 활성화.

---

## 진행 흐름 한눈에

```
   ┌──────────── Phase 1 (필수) ─────────────┐
   README → docs/01 → bootstrap-pi.sh
                                              │
   ┌──────────── Phase 2 (위임 모드 선택 시) ┘
   install-claude-code.sh
       → claude /login (또는 claude setup-token 무인 운영)
       (OpenClaw 가 OAuth 위임 모드로 호출. BYOK 모드면 스킵)
                                              │
   ┌──────────── Phase 3 (필수, 메인) ───────┘
   install-openclaw.sh
       → openclaw onboard --install-daemon  (BYOK 토큰 / 채널 / Gateway)
       → Telegram 봇 페어링 (선택, docs/03 §5)
       → examples/hello-agent (끝-끝 검증) ← 필수 체크포인트
                                              │
   ┌──────────── Phase 4 (필수) ─────────────┘
   systemctl --user enable openclaw  (onboard 가 깐 user 유닛 활성화)
       → docs/07 보안 베이스라인 통독
       → healthcheck.sh

   ─────────── 이후 (선택) ───────────
   docs/06 (성능 튜닝)
   recipes/* (시나리오 적용)
   examples/{github-pr-bot, log-triage}
```

---

## Phase 1 — 사전 점검 + 부트스트랩

### 1-1. README 한 번 훑기 (5분)

`README.md` 의 **사전 지식 / 요구 사양 / 보안 · 운영 주의사항 / 알려진 제약** 섹션만 읽기.

**필요한 자격증명** 미리 확인 — 다음 둘 중 하나:

- **(A) BYOK 모델 API key 1개**: OpenClaw 가 직접 호출. [Anthropic console](https://console.anthropic.com/) 의 API key (`sk-ant-...`), 또는 OpenAI / Google. 종량 과금.
- **(B) Claude Pro/Max 구독**: 이미 구독자라면 OAuth 위임 모드로 추가 청구 없이 OpenClaw 운영. Phase 2 의 `claude /login` 으로 인증. ([04-integration §1](./04-integration.md#1-두-인증-모드) — 모드 선택 가이드)
- **(선택) Telegram 봇 토큰**: 모바일에서 OpenClaw 에 메시지 보내는 채널. Phase 3 끝에 BotFather 로 만든다.

### 1-2. HW / OS 점검 — [`docs/01-prerequisites.md`](./01-prerequisites.md)

읽고 다음을 확인:

- 보드 = Pi 5 (8GB) 권장 / Pi 4 (4GB) 최소
- 저장소 = NVMe 권장 / microSD A2 64GB+ 최소
- 쿨링 = Pi 5 는 **액티브 쿨러 필수**
- 전원 = 27W USB-C PD 권장
- OS = RPiOS 64-bit Bookworm (또는 Ubuntu Server 24.04 ARM64)

✅ 체크: 다음 명령이 모두 정상 출력

```bash
uname -a                                  # aarch64 또는 arm64
cat /etc/os-release                       # PRETTY_NAME 확인
df -h /                                   # 여유 공간 16GB 이상
free -h                                   # MemTotal 4GB 이상
vcgencmd measure_temp 2>/dev/null         # 60℃ 이하 (Pi 만)
curl -fsS https://anthropic.com >/dev/null && echo OK
```

❌ 실패 시: [`docs/01-prerequisites.md`](./01-prerequisites.md) 의 해당 항목 / [`troubleshooting.md`](./troubleshooting.md) F절 (네트워크).

### 1-3. 저장소 클론 + 부트스트랩

> 📁 **경로 규약**: 본 가이드는 `/home/dzp/dzp_main/program/` 을 작업 베이스로 사용합니다. 다른 사용자/경로를 쓰려면 모든 `/home/dzp/dzp_main/program` 을 본인 경로로 치환하거나, 스크립트에 `OPENCLAW_PROGRAM_BASE=$HOME/your/path` 환경변수를 지정하세요.

```bash
# 작업 베이스 디렉토리 생성
mkdir -p /home/dzp/dzp_main/program
cd /home/dzp/dzp_main/program

git clone https://github.com/YawnsDuzin/openclaw-on-pi.git
cd /home/dzp/dzp_main/program/openclaw-on-pi

bash scripts/bootstrap-pi.sh
```

스크립트가 하는 일: apt 업데이트, 핵심 패키지 설치, Node.js 22 LTS (OpenClaw 최소 22.16 요구), `~/.claude` (700) / `/home/dzp/dzp_main/program/openclaw-work` / `~/.local/bin` 디렉토리 준비.

✅ 체크:

```bash
node --version            # v22.x (또는 v24.x)
python3 --version         # 3.x
ls -ld ~/.claude          # 권한이 700
ls -d /home/dzp/dzp_main/program/openclaw-work    # 디렉토리 존재
```

❌ 실패 시: [`troubleshooting.md`](./troubleshooting.md) C절 (빌드/의존성).

> ⏸ **여기서 멈춰도 됨** — 시간이 없으면 다음 세션에 Phase 2 부터 이어서.

---

## Phase 2 — Claude CLI 위임 OAuth (Pro/Max 구독 활용 시)

> 📌 **이 단계는 인증 모드 (B) 선택자만**. OpenClaw 가 `agentRuntime.id: "claude-cli"` 모드로 `claude` 서브프로세스를 띄워 OAuth 호출 — 구독 한도 안에서 운영 가능. API key (BYOK) 모드면 스킵. ([04-integration §1](./04-integration.md#1-두-인증-모드))

### 2-1. Claude CLI 설치

```bash
bash scripts/install-claude-code.sh

# 현재 셸에 PATH 적용 (스크립트가 ~/.bashrc 에 영구 등록은 자동 처리)
export PATH="$HOME/.npm-global/bin:$PATH"
```

✅ 체크:

```bash
claude --version          # 정상 출력 (2.1.x)
which claude              # ~/.npm-global/bin/claude
```

❌ 실패 시: [`troubleshooting.md`](./troubleshooting.md) C1 (npm EACCES) / C3 (Node 버전) / **C6 (PATH 누락 — `claude: 명령어를 찾을 수 없음`)**.

### 2-2. OAuth 인증 — `claude /login`

```bash
claude                    # TUI 열기
# TUI 안에서:
/login                    # OAuth 플로우 시작 → URL 출력
```

출력된 URL 을 **로컬 PC 브라우저** 에 붙여넣기 → Anthropic 로그인 → 받은 코드/토큰을 Pi 의 TUI 에 붙여넣기. 성공 메시지 (`✓ Logged in as ...`) 확인 후 `/exit`.

> 💡 구버전 (CLI 2.0 이하) 은 SSH `-L` 역포트포워딩 콜백 모드 — 그땐 [`scripts/oauth-tunnel.sh`](../scripts/oauth-tunnel.sh) 참고. 2.1.x 는 코드 입력 모드라 SSH 트릭 불필요.

✅ 체크:

```bash
ls -la ~/.claude/.credentials.json    # 권한 600
```

### 2-3. (강력 권장) 무인 운영 — `claude setup-token` 으로 장기 토큰

§2-2 의 OAuth access token TTL ≈ **8 시간**. 무인 24/7 운영이면 사람이 8 시간마다 재로그인하는 건 비현실 → 장기 토큰으로 우회:

```bash
claude setup-token        # 일회성 인터랙티브
```

이 모드는 access/refresh 사이클을 우회 → 만료 사실상 없음. `~/.claude/` 에 저장되고 OpenClaw 가 그대로 위임 사용. 자세한 절차 + 보안 트레이드오프는 [`docs/02 §3`](./02-claude-code-oauth.md#3-무인-운영--claude-setup-token-장기-토큰-강력-권장).

> ✅ **여기까지 = Phase 2 끝.** OpenClaw 가 위임 모드에서 본 토큰을 사용한다. 만료/문제 진단은 `openclaw doctor` (모델 auth 절).

---

## Phase 3 — OpenClaw + 첫 동작 검증

> 🔑 **Phase 2 를 스킵했다면 PATH 적용 필요**: 이번 세션에서 npm 글로벌 prefix 를 PATH 에 추가합니다 (영구 등록은 [3-1](#3-1-openclaw-설치-npm-글로벌) 의 스크립트가 자동).
>
> ```bash
> export PATH="$HOME/.npm-global/bin:$PATH"
> ```

### 3-0. BYOK API key 준비 (필수)

OpenClaw 는 BYOK — 본인의 API key 가 있어야 모델을 호출할 수 있습니다.

**Anthropic Claude (본 가이드 권장)**:

1. [console.anthropic.com](https://console.anthropic.com/) 로그인
2. 우상단 **Settings → API Keys → Create Key**
3. 이름 (예: `openclaw-pi`) + 워크스페이스 선택 → 생성
4. **이 키는 한 번만 보입니다.** 안전한 곳에 즉시 복사 (`sk-ant-...` 형태)
5. 결제 정보 미입력 시 free credit 만 사용 가능 → console 의 **Billing** 에서 카드 등록 + 사용량 한도 설정 (월 $20-50 권장으로 시작)

**OpenAI / Google** 도 가능 — 각 console 에서 API key 발급. 본 가이드는 Anthropic 을 가정.

### 3-1. OpenClaw 설치 (npm 글로벌)

```bash
bash scripts/install-openclaw.sh
```

스크립트가 하는 일: Node 22+ 검증 → `npm install -g openclaw@latest` → 최소 안전 버전 (2026.2.6) 검사 → 다음 단계 안내.

✅ 체크:

```bash
openclaw --version            # ≥ 2026.2.6 (CVE-2026-25253 패치 + VirusTotal 스캐너)
which openclaw                # ~/.npm-global/bin/openclaw
```

PATH 에 안 잡히면 → [`troubleshooting.md` C6](./troubleshooting.md#c6).

❌ 버전이 미달이면: `npm install -g openclaw@latest` 로 갱신. 갱신 후에도 미달이면 [`docs/07 §1`](./07-openclaw-hardening.md#1-알려진-cve--취약점-인벤토리) 의 CVE 인벤토리에서 영향 평가.

### 3-2. 대화형 온보딩 — `openclaw onboard`

OpenClaw 의 첫 실행은 **대화형 마법사**. 3-0 에서 받은 API key 와 다음 답들을 미리 준비:

```bash
openclaw onboard --install-daemon
```

마법사가 묻는 항목 (질문 순서/문구는 버전마다 다를 수 있음):

| 항목 | 본 가이드 권장 답 |
|---|---|
| 1순위 모델 | `anthropic/claude-sonnet-4-6` (또는 보유한 다른 provider) |
| Anthropic API key | 3-0 에서 받은 `sk-ant-...` 그대로 |
| Gateway 포트 | `18789` (기본) |
| Gateway 바인딩 | **`loopback`** (외부 노출 금지 — 권장 강제) |
| Gateway 인증 모드 | `token` |
| systemd daemon 설치 | `yes` (24/7 가동, user 모드 자동) |
| 메시징 채널 활성화 | **첫 가동은 `none`** (먼저 hello-agent 로 끝-끝 확인 후 [3-5](#3-5-메시징-채널-연결-telegram-bot-선택) 에서 추가) |

종료 후 확인:

```bash
ls -la ~/.openclaw/
# openclaw.json   (JSON5 설정)
# workspace/      (스킬·세션·로그)
# skills/         (managed 스킬)

# 보안 베이스라인 즉시 점검 (둘 다 "127.0.0.1" / "loopback" 이어야 ✅)
jq '.gateway.host, .gateway.bind' ~/.openclaw/openclaw.json

# onboard 가 user systemd 유닛을 깔았는지
systemctl --user list-unit-files openclaw.service
```

> 🚨 **여기서 잠깐 멈추고 통독**: [`docs/07-openclaw-hardening.md`](./07-openclaw-hardening.md) — 30분이면 다 읽힙니다. CVE / reverse-proxy / 스킬 리뷰 / 사고 대응. Gateway 띄우기 전 베이스라인 확인이 핵심.

❌ 실패 시: [`troubleshooting.md`](./troubleshooting.md) C 절 / [`docs/03 §3`](./03-openclaw-install.md#3-온보딩--openclaw-onboard).

### 3-3. Gateway 가동

3-2 의 `--install-daemon` 이 user systemd 유닛을 깔았으므로 다음 한 줄이면 됩니다:

```bash
systemctl --user start openclaw
sudo loginctl enable-linger "$USER"   # 로그아웃 후에도 살아있게 (1회만)
```

✅ 체크:

```bash
systemctl --user is-active openclaw      # active
(echo >/dev/tcp/127.0.0.1/18789) 2>&1 && echo "gateway up"
```

> 💡 user 유닛이 안 깔렸거나 (`--install-daemon` 옵션 생략 등) 디버깅하고 싶으면 별도 tmux 창에서 foreground 로:
> ```bash
> tmux new -s openclaw
> openclaw gateway --port 18789 --verbose
> # Ctrl+b d 로 분리, tmux attach -t openclaw 로 다시 보기
> ```

❌ 실패 시: [`troubleshooting.md`](./troubleshooting.md) B절 (systemd) — 특히 `journalctl --user -u openclaw -n 50 --no-pager` 로 원인 확인.

### 3-4. ★ 끝-끝 검증 — `examples/hello-agent`

**가장 중요한 체크포인트.** 이게 통과하면 OpenClaw 파이프라인 (스킬 매칭 → 모델 호출 → 채널 응답) 이 살아있다는 뜻.

```bash
cd /home/dzp/dzp_main/program/openclaw-work
cp -r /home/dzp/dzp_main/program/openclaw-on-pi/examples/hello-agent .
cd hello-agent

bash run.sh
```

스크립트가 하는 일 (예제 README 참고):

1. `~/.openclaw/skills/hello/SKILL.md` 설치 (frontmatter `name: hello` + `description: 단순 'hello' 응답`)
2. Gateway 가 떠 있는지 점검
3. `openclaw agent --message "hello" --thinking high` 호출
4. 응답이 정확히 `ok` 한 단어인지 검증

✅ 체크:

```bash
echo "[검증] 응답이 'ok' 한 단어:"  # run.sh 가 자체 검증 + 종료 코드 0
echo "[검증] gateway 로그에 skill=hello 매칭 기록:"
journalctl --user -u openclaw -n 30 --no-pager | grep -i 'skill.*hello' && echo OK
```

`bash run.sh` 가 종료 코드 0 으로 끝나면 ✅. **여기까지 됐으면 본 저장소의 약속이 실제로 동작한다는 증거.**

❌ 실패 시:
- gateway 미기동 → 3-3 의 `systemctl --user is-active openclaw` 재확인
- 모델 호출 실패 (401/429) → `~/.openclaw/openclaw.json` 의 `agents.defaults.model.primary` + 해당 provider API key (3-0 발급분) 가 유효한지 / 한도 초과 아닌지
- 스킬 매칭 안 됨 → `~/.openclaw/skills/hello/SKILL.md` 가 실제로 생겼는지 (`ls -la ~/.openclaw/skills/hello/`)

> ⏸ **여기서 멈춰도 됨** — Phase 4 의 보안 마무리만 끝내면 운영 가동.

### 3-5. 메시징 채널 연결 — Telegram bot (선택)

모바일에서 OpenClaw 에 말 걸고 싶으면 Telegram 봇으로 연결. **첫 1주는 본인만 페어링 (`dmPolicy: pairing` + `allowFrom` 본인 user id 만)**.

**A. BotFather 로 봇 만들기 (5분, 1회)**:

1. Telegram 앱에서 [@BotFather](https://t.me/BotFather) 검색해서 대화 시작
2. `/newbot` 입력 → BotFather 가 봇 이름과 username 을 묻습니다
   - 이름 (display name) — 자유롭게: 예 `My OpenClaw`
   - username — 반드시 `_bot` 으로 끝나야 함: 예 `mypi_openclaw_bot`
3. 마지막에 BotFather 가 **HTTP API 토큰** 을 줍니다: `123456789:ABC-DEF1234ghIklzyx57W2v1u123ew11` 형태 — 안전한 곳에 즉시 복사

**B. OpenClaw 에 등록**:

```bash
mkdir -p ~/.openclaw-secrets && chmod 700 ~/.openclaw-secrets
cat > ~/.openclaw-secrets/telegram.env <<'EOF'
TELEGRAM_BOT_TOKEN=123456789:ABC-...
EOF
chmod 600 ~/.openclaw-secrets/telegram.env

source ~/.openclaw-secrets/telegram.env
openclaw config set channels.telegram.enabled true
openclaw config set channels.telegram.botToken "$TELEGRAM_BOT_TOKEN"
openclaw config set channels.telegram.dmPolicy "pairing"

systemctl --user restart openclaw
```

**C. 페어링 (본인 user id 화이트리스트)**:

1. Telegram 앱에서 본인이 만든 봇 (`@mypi_openclaw_bot`) 검색 → `/start` 전송
2. OpenClaw 가 봇 응답에 페어링 코드를 표시 (예: `Pair code: 7HQK2`)
3. Pi 에서:

   ```bash
   openclaw pair --channel telegram --code 7HQK2
   ```

4. 페어링 끝 → 본인 Telegram user id 가 `channels.telegram.allowFrom` 에 자동 등록. 다른 사람이 같은 봇에 말 걸어도 차단.

✅ 체크:

```bash
# Telegram 봇에 메시지 보내기 (모바일 앱에서):
hello

# 응답이 ok 한 단어로 와야 함 (3-4 의 hello 스킬이 매칭)
```

❌ 실패 시: [`docs/03 §5`](./03-openclaw-install.md#5-메시징-채널-연결--telegram-예시) 의 트러블슈팅 / [`troubleshooting.md` E절](./troubleshooting.md#e-에이전트-호출--도구-사용).

---

## Phase 4 — 운영 전환 (systemd 24/7)

### 4-1. 영구 활성화 + 부팅 자동 시작

3-3 의 `systemctl --user start` 와 `loginctl enable-linger` 가 안 됐다면 이번에:

```bash
systemctl --user enable openclaw                 # 부팅 시 자동 시작
sudo loginctl enable-linger "$USER"              # 로그아웃해도 살아있게
```

✅ 체크:

```bash
systemctl --user is-active openclaw              # active
systemctl --user is-enabled openclaw             # enabled
loginctl show-user "$USER" --property=Linger     # Linger=yes
bash scripts/healthcheck.sh && echo "HC OK"      # 종료 코드 0 또는 2(warn-only)
```

❌ 실패 시: [`troubleshooting.md`](./troubleshooting.md) B절 (systemd) — B1 재시작 루프 / B2 권한.

> 💡 **시스템 모드** (가족 공용 / 강한 격리): [`docs/05` §2-1](./05-headless-ops.md#2-1-시스템-모드-사전-준비) 의 전용 사용자 + `/opt/openclaw` 절차. 1인 개인 운영이면 user 모드면 충분.

### 4-2. 보안 마무리 — [`docs/07`](./07-openclaw-hardening.md) 통독 + 체크리스트

본 가이드의 가장 중요한 마지막 단계입니다. [`docs/07-openclaw-hardening.md`](./07-openclaw-hardening.md) 의:

- **§2 Gateway 보안 베이스라인** — `host=127.0.0.1`, `bind=loopback`, `auth.mode=token` 적용 확인
- **§4 ClawHub 스킬 안전 정책** — 외부 스킬 설치 전 5단계 사람 리뷰
- **§5 자격증명 보호** — `~/.openclaw/` 권한 700 + 백업 분리
- **§6 Prompt Injection 운영 완화** — 메시지 출처 화이트리스트 + 1주일 그림자 가동

추가로 [`README` 보안 절](../README.md#보안--운영-주의사항) 의 일반 Pi 위생 (SSH 하드닝, 방화벽, fail2ban).

> ✅ **여기까지 = 운영 가동 완료.** OpenClaw 가 24/7 백그라운드에서 메시지에 응답하거나 cron 스킬을 돌립니다.

### 4-3. (위임 모드) 토큰 만료 모니터링

[Phase 2](#phase-2--claude-cli-위임-oauth-promax-구독-활용-시) 의 위임 모드를 쓴다면 `claude` 토큰 만료가 운영 침묵의 흔한 원인. `claude setup-token` 으로 장기 토큰을 받아두지 않았다면 access token 8h TTL 에 주의 — 헬스체크에 다음 체크 추가 권장:

```bash
openclaw doctor 2>&1 | grep -A3 'Model auth' | grep -q 'valid\|expiring' \
  || echo "[ALERT] OpenClaw model auth not valid"
```

자세한 진단/복구는 [`docs/02 §4`](./02-claude-code-oauth.md#4-토큰-만료--재인증-3-안-쓸-때).

---

## 이후 (선택)

| 목적 | 가는 곳 |
|---|---|
| 성능 / 발열 / 메모리 압박 잡기 | [`docs/06-performance-tuning.md`](./06-performance-tuning.md) |
| 자율 코딩 루프 24/7 활성화 | [`recipes/auto-coding-loop.md`](../recipes/auto-coding-loop.md) |
| 외부에서 Pi 조작 (모바일) | [`recipes/remote-agent-control.md`](../recipes/remote-agent-control.md) |
| cron / systemd timer 정기 작업 | [`recipes/scheduled-agent-tasks.md`](../recipes/scheduled-agent-tasks.md) |
| 역할별 봇 분리 (트리아지/코더/리포터) | [`recipes/multi-agent-orchestration.md`](../recipes/multi-agent-orchestration.md) |
| GPIO / MQTT 센서 통합 | [`recipes/iot-bridge.md`](../recipes/iot-bridge.md) |
| GitHub 이슈 → PR 자동화 (예제) | [`examples/github-pr-bot/`](../examples/github-pr-bot/) — **첫 가동 시 `PR_BOT_DRY_RUN=1` 1주일 그림자** |
| journald 로그 트리아지 (예제) | [`examples/log-triage/`](../examples/log-triage/) — **첫 가동 시 `LOG_TRIAGE_PUBLISH=stdout` 1주일** |

---

## 막혔을 때

| 증상 카테고리 | 점프 |
|---|---|
| OAuth / 인증 / 토큰 (OpenClaw 위임 모드 포함) | [`troubleshooting.md`](./troubleshooting.md) **A절** |
| systemd 유닛 / 워치독 | **B절** |
| npm / Node 빌드 / OpenClaw 설치 / PATH | **C절** |
| OOM / throttle / 디스크 | **D절** |
| OpenClaw 에이전트 호출 / 스킬 매칭 / 도구 거부 | **E절** |
| 네트워크 / DNS / SSL | **F절** |
| 보안 (fail2ban / credentials 누출) | **G절** |

위 표에 없는 케이스는 [bug 이슈 템플릿](../.github/ISSUE_TEMPLATE/bug.yml) 으로 신고.

---

## 진척 체크리스트

Phase 별로 끝났는지 빠르게 확인:

- [ ] **P1 (필수)** `bash scripts/bootstrap-pi.sh` 통과 + `node --version` ≥ v22
- [ ] **P2 (위임 모드 시 필수)** `claude` TUI → `/login` 성공 + `openclaw doctor` 의 Model auth 가 `valid` 또는 `expiring (Nh)`
- [ ] **P3a (필수)** 인증 모드 선택 (BYOK 또는 위임) + `openclaw onboard --install-daemon` 종료 + `~/.openclaw/openclaw.json` 생성 + `gateway.bind` = `"loopback"`
- [ ] **P3b (필수)** `systemctl --user is-active openclaw` = `active` + `examples/hello-agent` `run.sh` 종료 코드 0
- [ ] **P3c (선택)** Telegram 봇 페어링 → 모바일에서 `hello` 보내면 `ok` 응답
- [ ] **P4 (필수)** `systemctl --user is-enabled openclaw` = `enabled` + `loginctl Linger=yes` + `docs/07` 통독

필수 4개 (P1/P3a/P3b/P4) 가 모두 ✅ 면 본 저장소의 약속이 당신의 Pi 에서 살아있는 상태입니다.

> 🚨 **마지막 보안 확인**: 첫 일주일은 다음 조건으로 그림자 가동하세요:
> - `channels.*.dmPolicy: "pairing"` + `allowFrom` 본인만
> - 신규 스킬 자동 설치 금지 (`openclaw skills install` 은 수동만)
> - `gateway.bind: "loopback"` 유지 (외부 노출 금지)
>
> 이 셋이 깨지면 [docs/07 §1](./07-openclaw-hardening.md#1-알려진-cve--취약점-인벤토리) 의 위험에 노출됩니다.

# 00 — Quickstart (처음 사용자 가이드)

> 이 문서 한 페이지로 **빈 Pi → OpenClaw + Claude Code 24/7 가동** 까지 끝낸다.
> 각 단계마다 검증 명령과 실패 시 점프 위치가 명시되어 있다. **위에서 아래로 순서대로** 진행하면 된다.

⚠ 검증 환경: Raspberry Pi 5 (8GB) + Raspberry Pi OS 64-bit Bookworm. Pi 4 (4GB) / Ubuntu Server 24.04 ARM64 호환은 가능하지만 일부 단계가 더 오래 걸릴 수 있다.

---

## 진행 시간 예상

| 구간 | 예상 시간 |
|---|---|
| Phase 1 (사전 점검 + 부트스트랩) | 15–25 분 |
| Phase 2 (Claude Code + OAuth) | 5–10 분 |
| Phase 3 (OpenClaw + 첫 동작 검증) | 10–15 분 |
| Phase 4 (운영 전환 — systemd) | 15–20 분 |
| **총 (운영 가동까지)** | **약 1시간** |

이후 (선택): 성능 튜닝 / 레시피 적용 / 추가 예제 활성화.

---

## 진행 흐름 한눈에

```
   ┌──────────── Phase 1 ────────────┐
   README → docs/01 → bootstrap-pi.sh
                                     │
   ┌──────────── Phase 2 ────────────┘
   install-claude-code.sh
       → docs/02 + oauth-tunnel.sh + claude login
                                     │
   ┌──────────── Phase 3 ────────────┘
   install-openclaw.sh
       → docs/03 (설정 복사)
       → examples/hello-agent (끝-끝 검증) ← 필수 체크포인트
                                     │
   ┌──────────── Phase 4 ────────────┘
   docs/04 (통합 패턴 학습)
       → docs/05 (systemd 전환) ← 운영 가동
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
구독은 **Claude Pro 또는 Max** 가 전제입니다 (Free 는 한도 부족).

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

스크립트가 하는 일: apt 업데이트, 핵심 패키지 설치, Node.js 20 LTS, `~/.claude` (700) / `/home/dzp/dzp_main/program/openclaw-work` / `~/.local/bin` 디렉토리 준비.

✅ 체크:

```bash
node --version            # v20.x
python3 --version         # 3.x
ls -ld ~/.claude          # 권한이 700
```

❌ 실패 시: [`troubleshooting.md`](./troubleshooting.md) C절 (빌드/의존성).

> ⏸ **여기서 멈춰도 됨** — 시간이 없으면 다음 세션에 Phase 2 부터 이어서.

---

## Phase 2 — Claude Code + OAuth

### 2-1. Claude Code CLI 설치

```bash
bash scripts/install-claude-code.sh

# 현재 셸에 PATH 적용 (스크립트가 ~/.bashrc 에 영구 등록은 자동 처리)
export PATH="$HOME/.npm-global/bin:$PATH"
```

✅ 체크:

```bash
claude --version          # 정상 출력
which claude              # ~/.npm-global/bin/claude (또는 PATH 의 다른 곳)
```

❌ 실패 시: [`troubleshooting.md`](./troubleshooting.md) C1 (npm EACCES) / C3 (Node 버전) / **C6 (PATH 누락 — `claude: 명령어를 찾을 수 없음`)**.

### 2-2. OAuth 1회 인증 — [`docs/02-claude-code-oauth.md`](./02-claude-code-oauth.md)

[`docs/02`](./02-claude-code-oauth.md) §1 ("본질") 만 먼저 읽고 (왜 SSH 트릭이 필요한지), 다음 절차:

1. **로컬 PC** 에서 SSH 세션을 새로 엶:

   ```bash
   ssh -L 54545:localhost:54545 <user>@<pi-host>
   ```

2. **Pi** 에서 안내 출력 (선택):

   ```bash
   bash scripts/oauth-tunnel.sh
   ```

3. **Pi** 에서 인증:

   ```bash
   claude login
   ```

   출력된 `https://...` URL 을 **로컬 PC 브라우저** 에 붙여넣기 → Anthropic 로그인 → 콜백이 SSH 터널을 타고 Pi 에 도달.

4. 권한 정리:

   ```bash
   chmod 700 ~/.claude
   chmod 600 ~/.claude/credentials.json
   ```

✅ 체크:

```bash
ls -la ~/.claude/credentials.json     # 권한 600
claude -p "say 'ok' and nothing else" # ok 한 단어
```

❌ 실패 시: [`troubleshooting.md`](./troubleshooting.md) A절 (OAuth) — A1 콜백 안 옴 / A2 redirect_uri / A3 시계 동기화.

> ✅ **첫 결제·인증의 끝.** 이 이후는 토큰 만료 전까지 재인증 불필요.

---

## Phase 3 — OpenClaw + 첫 동작 검증

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

OpenClaw 의 첫 실행은 **대화형 마법사**. BYOK 토큰 / 채널 / Gateway 토큰을 한 번에 물어 `~/.openclaw/openclaw.json` 을 생성.

```bash
openclaw onboard --install-daemon
```

대화형으로 묻는 항목 (질문 순서/문구는 버전마다 다를 수 있음):

| 항목 | 본 가이드 권장 답 |
|---|---|
| 1순위 모델 | `anthropic/claude-sonnet-4-6` (또는 보유한 다른 provider) |
| Anthropic API key | 본인 키 — 없으면 console.anthropic.com 에서 발급 |
| Gateway 포트 | `18789` (기본) |
| Gateway 바인딩 | **`loopback`** (외부 노출 금지 — 권장 강제) |
| systemd daemon 설치 | `yes` (24/7 가동) |
| 메시징 채널 활성화 | **`Telegram only` + dmPolicy `pairing`** (첫 1주는 본인 페어링만) |

종료 후 확인:

```bash
ls -la ~/.openclaw/
# openclaw.json   (JSON5 설정)
# workspace/      (스킬·세션·로그)
# skills/         (managed 스킬)

# 보안 베이스라인 즉시 점검
jq '.gateway.host, .gateway.bind' ~/.openclaw/openclaw.json
# 둘 다 "127.0.0.1" / "loopback" 이어야 ✅
```

> 🚨 **여기서 잠깐 멈추고 통독**: [`docs/07-openclaw-hardening.md`](./07-openclaw-hardening.md) — 30분이면 다 읽힙니다. CVE / reverse-proxy / 스킬 리뷰 / 사고 대응. Gateway 띄우기 전 베이스라인 확인이 핵심.

❌ 실패 시: [`troubleshooting.md`](./troubleshooting.md) C 절 / [`docs/03 §3`](./03-openclaw-install.md#3-온보딩--openclaw-onboard).

### 3-3. Gateway 띄우고 페어링

별도 tmux 창 또는 백그라운드에서:

```bash
openclaw gateway --port 18789 --verbose
```

Telegram BotFather 로 봇 생성 → `bot token` 을 `~/.openclaw-secrets/env` 에 저장 (권한 600) → onboard 가 안 했으면 수동으로:

```bash
export TELEGRAM_BOT_TOKEN="123456:abcdef..."
openclaw config set channels.telegram.enabled true
openclaw config set channels.telegram.botToken "$TELEGRAM_BOT_TOKEN"
openclaw config set channels.telegram.dmPolicy "pairing"

# Telegram 에서 본인 봇에게 /start → 표시된 코드를 입력
openclaw pair --channel telegram --code <코드>
```

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
- gateway 미기동 → 별도 창에서 `openclaw gateway --verbose` 확인
- 모델 호출 실패 → `~/.openclaw/openclaw.json` 의 `agents.defaults.model.primary` + 해당 provider API key 점검
- 스킬 매칭 안 됨 → `description` 이 명확한지, `~/.openclaw/skills/hello/SKILL.md` 가 실제로 생겼는지

> ⏸ **여기서 멈춰도 됨** — 운영 전환은 Phase 4. 지금까지가 "맛보기" 라면 충분.

---

## Phase 4 — 운영 전환 (systemd 24/7)

### 4-1. 통합 패턴 한 번 읽기 — [`docs/04-integration.md`](./04-integration.md)

15분 분량. **꼭 읽어야 하는 절**:

- §2-1 단발 위임 패턴 — `claude -p --add-dir ... --output-format json`
- §3 CLAUDE.md 활용
- §4 권한 화이트리스트 (settings.json `permissions.deny` 우선 원칙)

### 4-2. systemd 전환 — [`docs/05-headless-ops.md`](./05-headless-ops.md)

**권장 (user 모드)**: 3-2 의 `openclaw onboard --install-daemon` 가 이미 user systemd 유닛을 만들었다. 그저 활성화만:

```bash
systemctl --user start openclaw
systemctl --user enable openclaw

# 로그아웃해도 살아있게
sudo loginctl enable-linger "$USER"
```

**시스템 모드** (가족 공용 / 격리 필요): [`docs/05` §2-1](./05-headless-ops.md#2-1-시스템-모드-사전-준비) 의 전용 사용자 + `/opt/openclaw` 절차 — 1인 운영이면 user 모드가 단순하니 그쪽으로.

✅ 체크 (user 모드 기준):

```bash
systemctl --user is-active openclaw            # active
journalctl --user -u openclaw -n 20 --no-pager
bash scripts/healthcheck.sh && echo "HC OK"    # 종료 코드 0 또는 2(warn-only)
```

❌ 실패 시: [`troubleshooting.md`](./troubleshooting.md) B절 (systemd) — B1 재시작 루프 / B2 권한.

### 4-3. 보안 마무리

[`README.md` 의 "보안 · 운영 주의사항"](../README.md#보안--운영-주의사항) 의 체크박스 5개 — SSH 하드닝 / 방화벽 / 사용자 분리 / 토큰 보호 / 백업.
세부 절차는 [`docs/05-headless-ops.md`](./05-headless-ops.md) §4 ("원격 접근").

> ✅ **여기까지 = 운영 가동 완료.** 24/7 백그라운드에서 OpenClaw 가 큐를 돌립니다.

---

## 이후 (선택)

| 목적 | 가는 곳 |
|---|---|
| 성능 / 발열 / 메모리 압박 잡기 | [`docs/06-performance-tuning.md`](./06-performance-tuning.md) |
| 자율 코딩 루프 24/7 활성화 | [`recipes/auto-coding-loop.md`](../recipes/auto-coding-loop.md) |
| 외부에서 Pi 조작 (모바일) | [`recipes/remote-vibe-coding.md`](../recipes/remote-vibe-coding.md) |
| cron / systemd timer 정기 작업 | [`recipes/scheduled-agent-tasks.md`](../recipes/scheduled-agent-tasks.md) |
| 역할별 봇 분리 (트리아지/코더/리포터) | [`recipes/multi-agent-orchestration.md`](../recipes/multi-agent-orchestration.md) |
| GPIO / MQTT 센서 통합 | [`recipes/iot-bridge.md`](../recipes/iot-bridge.md) |
| GitHub 이슈 → PR 자동화 (예제) | [`examples/github-pr-bot/`](../examples/github-pr-bot/) — **첫 가동 시 `PR_BOT_DRY_RUN=1` 1주일 그림자** |
| journald 로그 트리아지 (예제) | [`examples/log-triage/`](../examples/log-triage/) — **첫 가동 시 `LOG_TRIAGE_PUBLISH=stdout` 1주일** |

---

## 막혔을 때

| 증상 카테고리 | 점프 |
|---|---|
| OAuth / 인증 / 토큰 | [`troubleshooting.md`](./troubleshooting.md) **A절** |
| systemd 유닛 / 워치독 | **B절** |
| npm / pip / Node 빌드 | **C절** |
| OOM / throttle / 디스크 | **D절** |
| `claude` 호출 / 큐 / 권한 거부 | **E절** |
| 네트워크 / DNS / SSL | **F절** |
| 보안 (fail2ban / credentials 누출) | **G절** |

위 표에 없는 케이스는 [bug 이슈 템플릿](../.github/ISSUE_TEMPLATE/bug.yml) 으로 신고.

---

## 진척 체크리스트

Phase 별로 끝났는지 빠르게 확인:

- [ ] **P1** `bash scripts/bootstrap-pi.sh` 통과 + `node --version` ≥ v22
- [ ] **P2** `claude -p "say ok"` → `ok` 출력 (Claude Code CLI 가 살아있음 — 선택)
- [ ] **P3a** `openclaw onboard --install-daemon` 종료 + `~/.openclaw/openclaw.json` 생성 + `gateway.bind` = `"loopback"`
- [ ] **P3b** `examples/hello-agent` `run.sh` 종료 코드 0 (스킬 매칭 + agent 응답 `ok`)
- [ ] **P4** `systemctl --user is-active openclaw` = `active` + `healthcheck.sh` 종료 코드 0/2

5개 모두 ✅ 면 본 저장소의 약속이 당신의 Pi 에서 살아있는 상태입니다.

> 🚨 마지막으로 [`docs/07-openclaw-hardening.md`](./07-openclaw-hardening.md) §2 (gateway 보안 베이스라인) 와 §4 (스킬 리뷰 정책) 을 한 번 더 통독하세요 — 첫 일주일은 dmPolicy=pairing + allowFrom 본인만 + 신규 스킬 자동 설치 금지 상태로 그림자 가동.

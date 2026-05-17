# 03 — OpenClaw 설치

> OpenClaw (https://github.com/openclaw/openclaw) 설치 · 첫 온보딩 · 첫 동작.
>
> ⚠ 본 문서는 2026-05-16 재작성 라운드 산출물입니다. 1차 라운드는 OpenClaw 를 Python/pip 기반으로 잘못 가정했으나, 실제는 **TypeScript / Node.js (pnpm)** 기반입니다. PyPI 의 `openclaw` 는 별개 프로젝트 (cmdop.com 의 SDK 플러그인) 이며 본 가이드와 무관합니다.

⚠ 검증 환경: Raspberry Pi 5 (8GB) + Raspberry Pi OS 64-bit Bookworm + Node.js 22 (이 가이드의 `bootstrap-pi.sh` 가 깐 버전). 정확한 절차는 OpenClaw 공식 README · `docs.openclaw.ai` 가 우선이며 충돌 시 본 문서를 갱신할 것.

---

## 1. 사전

- [01 — Prerequisites](./01-prerequisites.md) 완료 + `bash scripts/bootstrap-pi.sh` 가 끝난 상태
- Node.js **22.16+** (24 권장) 설치 — `node --version` 으로 확인
- [02 — Claude Code OAuth](./02-claude-code-oauth.md) 인증은 *선택* — OpenClaw 는 BYOK 다중 모델 라우팅이라 Claude 가 필수는 아니다. 단 본 가이드의 기본 권장은 Anthropic Claude

---

## 2. 설치

```bash
bash scripts/install-openclaw.sh
```

스크립트가 하는 일:

- Node 22+ 검증
- `npm install -g openclaw@latest` (사용자 prefix `~/.npm-global`)
- 설치된 버전을 최소 안전 버전 (`2026.2.6`, [CVE-2026-25253](./07-openclaw-hardening.md) 패치 + VirusTotal 스캐너 포함) 과 비교
- 다음 단계 안내 출력

설치 확인:

```bash
which openclaw                  # ~/.npm-global/bin/openclaw
openclaw --version              # ≥ 2026.2.6 권장
```

PATH 가 안 잡혔다면 [troubleshooting.md C6](./troubleshooting.md#c6).

---

## 3. 온보딩 — `openclaw onboard`

OpenClaw 의 첫 실행은 **대화형 온보딩** 이다. 다음 항목들을 한 번에 묻고 `~/.openclaw/openclaw.json` 을 자동 생성한다:

- 사용 모델 (BYOK — Anthropic / OpenAI / Google / Local)
- 메시징 채널 (Telegram / Discord / Slack 등 — 보통 1개로 시작)
- Gateway 포트 / 인증 토큰
- systemd / daemon 설치 여부

```bash
openclaw onboard --install-daemon
```

종료 후 확인:

```bash
ls -la ~/.openclaw/
# openclaw.json     (설정, JSON5)
# workspace/        (스킬·세션·로그)
# skills/           (managed 스킬)
```

> 💡 `--install-daemon` 은 systemd 유저 유닛까지 설치. 시스템 전역 서비스로 두려면 본 가이드 [`docs/05-headless-ops.md`](./05-headless-ops.md) 의 별도 설치 절차를 따른다 (OpenClaw 가 만드는 user-mode daemon 과는 별개).

---

## 4. 설정 파일 — `~/.openclaw/openclaw.json`

본 저장소가 제공하는 예제: [`configs/openclaw.example.json5`](../configs/openclaw.example.json5). JSON5 라 주석/트레일링 콤마 허용.

핵심 키:

| 키 | 의미 | 본 가이드 권장 |
|---|---|---|
| `agents.defaults.workspace` | 워크스페이스 경로 | `~/.openclaw/workspace` (기본) |
| `agents.defaults.model.primary` | 1순위 모델 | `anthropic/claude-sonnet-4-6` |
| `agents.defaults.model.fallbacks` | 폴백 모델 목록 | `anthropic/claude-opus-4-7`, `openai/gpt-5-codex` |
| `gateway.host` | 바인딩 호스트 | **`127.0.0.1`** (loopback 강제) |
| `gateway.port` | 게이트웨이 포트 | `18789` |
| `gateway.bind` | 바인딩 정책 | **`loopback`** (외부 노출 금지) |
| `gateway.auth.mode` | 인증 모드 | `token` |
| `gateway.auth.token` | 게이트웨이 토큰 | OS env 로 주입 |
| `gateway.trustedProxies` | reverse proxy 화이트리스트 | 비워둘 것 (외부 노출 시 [docs/07](./07-openclaw-hardening.md) 참고) |
| `channels.telegram.enabled` | 텔레그램 채널 활성화 | 첫 1주는 `false` 로 두고 dry-run |
| `browser.ssrfPolicy.dangerouslyAllowPrivateNetwork` | SSRF 보호 | **`false`** 유지 |

> 🚨 **반드시 변경**: `gateway.auth.token` / `hooks.token` / `channels.*.botToken` 은 본 파일에 평문 쓰지 말고 OS env / systemd `EnvironmentFile` 로 주입. OpenClaw 는 `~/.openclaw/` 하위에 자격증명을 *평문* 저장한다 — 머신 침해 시 모든 연결 계정이 노출된다.

---

## 5. 메시징 채널 연결 — Telegram 예시 (선택)

가장 짧은 끝-끝 검증 경로는 **Telegram bot 으로 본인 계정에서만 페어링** 하는 것입니다. WhatsApp / iMessage / Signal 등은 각자 다른 페어링 절차 + 추가 의존성이 필요하므로 첫 가동은 Telegram 만 권장.

### 5-1. BotFather 로 봇 만들기 (5분, 1회)

Telegram 자체에 봇 관리용 공식 봇 [@BotFather](https://t.me/BotFather) 가 있습니다.

1. Telegram 앱에서 **BotFather** 검색 (정확히 `@BotFather`, 파란 체크 표시 확인) → 대화 시작
2. `/newbot` 입력
3. BotFather 의 질문 두 개에 답:
   - **이름 (display name)** — 자유: 예 `My Pi OpenClaw`
   - **username** — 반드시 `_bot` 으로 끝나야 함: 예 `mypi_openclaw_bot` (전 세계 유일해야 함, 거부되면 다른 이름)
4. 마지막에 BotFather 가 **HTTP API 토큰** 을 줍니다 — `123456789:ABC-DEF1234ghIklzyx57W2v1u123ew11` 형태. **이 토큰이 곧 봇 자체의 비밀번호** 이므로 깃에 커밋하지 말고 환경변수로만 다룸.

### 5-2. OpenClaw 에 봇 토큰 등록

`~/.openclaw-secrets/telegram.env` 에 안전 보관 (권한 600):

```bash
mkdir -p ~/.openclaw-secrets && chmod 700 ~/.openclaw-secrets
cat > ~/.openclaw-secrets/telegram.env <<'EOF'
TELEGRAM_BOT_TOKEN=123456789:ABC-DEF1234ghIklzyx57W2v1u123ew11
EOF
chmod 600 ~/.openclaw-secrets/telegram.env

source ~/.openclaw-secrets/telegram.env
openclaw config set channels.telegram.enabled true
openclaw config set channels.telegram.botToken "$TELEGRAM_BOT_TOKEN"
openclaw config set channels.telegram.dmPolicy "pairing"   # 페어링 안 된 사용자 차단

systemctl --user restart openclaw     # 새 채널 설정 반영
```

### 5-3. 페어링 (본인 user id 화이트리스트)

1. Telegram 앱에서 본인이 만든 봇 (`@mypi_openclaw_bot`) 을 검색해서 **시작 (Start)** 또는 `/start` 전송
2. OpenClaw 가 봇 응답으로 페어링 코드를 표시 (예: `Pair code: 7HQK2`)
3. Pi 에서:

   ```bash
   openclaw pair --channel telegram --code 7HQK2
   ```

4. 페어링 끝 → 본인 Telegram user id 가 자동으로 `channels.telegram.allowFrom` 에 등록. 다른 사람이 같은 봇에 말 걸어도 차단.

### 5-4. 검증

Telegram 앱에서 본인 봇에 메시지:

```
hello
```

응답: `ok` (3-4 의 hello 스킬이 매칭되었다면). 안 오면 [troubleshooting E절](./troubleshooting.md#e-에이전트-호출--도구-사용).

### 5-5. 봇 토큰 분실/누출 대응

BotFather 에서 `/revoke` → 새 토큰 발급 → `telegram.env` 갱신. 본 가이드 [`docs/07 §7`](./07-openclaw-hardening.md#7-사고-시-체크리스트) 의 사고 체크리스트.

---

## 6. 첫 동작 — `openclaw agent`

본 저장소 [`examples/hello-agent`](../examples/hello-agent/) 의 `bash run.sh` 가 자동 검증해주므로 그쪽이 가장 빠른 길입니다. 본 절은 원리 이해용.

**전제**: 3 의 `openclaw onboard --install-daemon` 으로 user systemd 유닛이 깔리고 `systemctl --user start openclaw` 로 가동 중. 그렇지 않으면 별도 tmux 창에서 `openclaw gateway --port 18789 --verbose` 를 띄워둬야 합니다 (foreground 와 systemd 유닛은 동시에 같은 포트를 쓸 수 없으므로 **택일**).

```bash
# 1) 임의의 스킬 정의 (~/.openclaw/skills/hello/SKILL.md)
mkdir -p ~/.openclaw/skills/hello
cat > ~/.openclaw/skills/hello/SKILL.md <<'MD'
---
name: hello
description: 단순 인사 응답. 'hello' 메시지에 'ok' 한 단어로 답한다.
---
사용자 메시지가 정확히 `hello` 이면 `ok` 라고만 답하라. 그 외는 무시.
MD

# 2) Gateway 가 살아있는지 확인
systemctl --user is-active openclaw    # active (onboard --install-daemon 후)
# 또는 foreground 모드면:
#   openclaw gateway --port 18789 --verbose
# (이 경우 systemctl 의 openclaw 는 미리 stop)

# 3) 에이전트 호출
openclaw agent --message "hello" --thinking high
```

기대:

- 응답 본문이 정확히 `ok`
- 로그에 스킬 `hello` 가 매칭되었다는 줄: `journalctl --user -u openclaw -n 30 --no-pager | grep -i 'skill.*hello'`

---

## 7. 권한 / 안전장치 — Claude Code 와의 관계

OpenClaw 는 BYOK 로 여러 모델을 자체 라우팅한다. Anthropic Claude 를 primary 로 두면 OpenClaw 가 Claude API 를 직접 호출한다 — **Claude Code CLI 와는 별도 경로** 다.

[02 — Claude Code OAuth](./02-claude-code-oauth.md) 의 토큰은:

- 본 가이드의 *대화형 vibe-coding* 용 Claude Code CLI 호출에만 쓰인다 (예: `recipes/remote-vibe-coding`).
- OpenClaw 가 모델로 부르는 Anthropic API 와는 다른 인증 경로 — OpenClaw 의 BYOK 는 자체 API key (또는 onboarding 으로 발급한 OAuth) 를 사용한다.

따라서 본 호스트에는 두 종류의 자격증명이 공존할 수 있다:

| 위치 | 용도 |
|---|---|
| `~/.claude/credentials.json` | Claude Code CLI 가 사용 (vibe-coding) |
| `~/.openclaw/openclaw.json` (또는 OS env) | OpenClaw 가 모델 호출에 사용 |

---

## 8. 자율 도구 사용 제한

OpenClaw 의 셀링 포인트인 *자율 셸 실행 + 스킬 자가 생성* 은 동시에 가장 큰 위험이다. **본 가이드의 운영 기본값**:

- `gateway.bind: "loopback"` — 외부 노출 금지
- `channels.*.dmPolicy: "pairing"` — 페어링 안 된 사용자 차단
- `channels.*.allowFrom: [...]` — 본인만 화이트리스트
- `browser.ssrfPolicy.dangerouslyAllowPrivateNetwork: false`
- ClawHub 외부 스킬 설치 전 **사람 리뷰** 강제 (자동 설치 금지)

자세한 보안 절차는 [`docs/07-openclaw-hardening.md`](./07-openclaw-hardening.md). CVE 인벤토리 + reverse proxy 인증 우회 (93.4% 영향) + ClawHub 악성 스킬 230+ 건 사례까지 포함.

---

## 9. 다음 단계

- [`examples/hello-agent`](../examples/hello-agent/) — 끝-끝 동작 검증 (체크포인트)
- [04 — Integration](./04-integration.md) — Claude Code CLI 와의 관계, 채널 라우팅, 스킬 작성 패턴
- [05 — Headless Ops](./05-headless-ops.md) — systemd 로 24/7 가동
- [07 — Hardening](./07-openclaw-hardening.md) — 외부 노출 / reverse proxy / 자격증명 보호

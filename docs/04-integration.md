# 04 — Integration: OpenClaw 인증 모드 + Claude CLI 위임

> OpenClaw 의 **두 가지 인증 모드** (BYOK API key vs Claude CLI OAuth 위임) 와 그에 따른 호출 경로 · 비용 구조 · 함정.

⚠ 검증 환경: OpenClaw 2026.5.x, Claude Code CLI 2.1.x. 2026-05-17 Pi 5 (8GB) 에서 두 모드 모두 동작 확인.

> 📜 2026-05-16 1차 라운드는 "OpenClaw 가 코드 작성을 Claude Code 에 위임" + "OpenClaw 는 OAuth 못 씀" 으로 잘못 가정. 2026-05-17 Pi 검증으로 정정 — OpenClaw 는 [Anthropic sanctioned 모드](https://docs.openclaw.ai/concepts/oauth) 로 Claude CLI OAuth 를 위임 사용 가능하다.

---

## 1. 두 인증 모드

| 모드 | 자격증명 위치 | 청구 | 만료 관리 |
|---|---|---|---|
| **A. API key (BYOK)** | `~/.openclaw/openclaw.json` (또는 OS env 주입) | 종량, provider 콘솔에서 한도 설정 | API key 회수까지 유효 |
| **B. Claude CLI 위임 (OAuth)** | `~/.claude/.credentials.json` (Claude CLI 가 관리) | 구독 + 추가 사용량 풀 | access token 8h, refresh 불안정 — `claude setup-token` 으로 장기 토큰 권장 |

설정 (`~/.openclaw/openclaw.json`):

```json5
// A. BYOK
{
  agents: {
    defaults: {
      agentRuntime: { id: "anthropic-api" },        // 또는 openai-api, google-api ...
      model: { primary: "anthropic/claude-sonnet-4-6" },
    },
  },
  auth: {
    profiles: {
      "anthropic:api-key": {
        provider: "anthropic-api",
        mode: "api-key",
        // 토큰은 env 로 주입 — config 평문 금지
      },
    },
  },
}
```

```json5
// B. Claude CLI 위임 (OAuth)
{
  agents: {
    defaults: {
      agentRuntime: { id: "claude-cli" },           // ← 위임 모드
      model: { primary: "anthropic/claude-haiku-4-5" },  // 빠르고 저비용 권장
    },
  },
  auth: {
    profiles: {
      "anthropic:claude-cli": {
        provider: "claude-cli",
        mode: "oauth",
        // 실제 토큰은 ~/.claude/.credentials.json — Claude CLI 가 관리
      },
    },
  },
}
```

`openclaw onboard` 또는 `openclaw configure` 마법사가 둘 중 하나를 묻는다. 변경: `openclaw configure` 재실행.

---

## 2. 어느 모드 선택?

| 상황 | 권장 |
|---|---|
| 이미 Claude Pro/Max 구독자 + 가벼운 봇 운영 | **B** (위임) — 추가 청구 없음 |
| 자율 코딩 루프 / 헤비 워크로드 | **A** (BYOK) — 사용량 추적/예산 통제 쉬움 |
| 다중 provider (Anthropic + OpenAI fallback 등) | **A** (BYOK) — provider 별 API key 자유 |
| 무인 24/7 운영 (사람 개입 최소) | **A** 또는 **B + `claude setup-token`** — 8h 만료 회피 |
| 새 사용자 + 비용 예산 명확히 잡고 싶음 | **A** — Anthropic console 에 월 한도 설정 |

> 💡 **두 모드 동시 운용**도 가능 (primary + fallback). 다만 토큰 관리 복잡도 증가 — 보통 하나로 통일이 깔끔.

---

## 3. 호출 경로 (OpenClaw 의 실제 동작)

### 3-1. 메시지 수신 → 스킬 매칭

```
[Telegram bot] ── "deploy staging" ──► [openclaw gateway :18789]
                                                │
                                                ▼
                              스킬 매칭 (SKILL.md description XML)
                                                │
                                                ▼
                                  모드 A: provider API 직접
                                  모드 B: spawn(claude -p) → claude CLI 가 OAuth 로 호출
                                                │
                                                ▼
                                  도구 호출 (셸/파일/브라우저/세션)
                                                │
                                                ▼
                                  응답 → 같은 채널 thread 회신
```

스킬 매칭 방식:

- **Auto**: SKILL.md 의 `description:` 이 시스템 프롬프트에 XML 로 주입 → 모델이 이름으로 호출
- **명시 슬래시 명령**: SKILL.md frontmatter 에 `user-invocable: true` 면 메시지가 `/skill-name` 으로 시작할 때 직접 디스패치

### 3-2. 모드 B (위임) 의 빌링 함정

⚠ **첫 운영자 100% 가 부딪히는 함정**:

`claude -p` (Claude CLI 의 programmatic 모드) 는 대화형 사용과 **다른 청구 풀** — "추가 사용량"(extra usage) 풀 — 을 통해 빌링된다. Anthropic 이 자동화 트래픽에 명시적 동의 게이트를 둔 구조.

claude.ai/settings/usage 의 **추가 사용량 토글이 OFF 면 잔액이 있어도 거부** → `out of extra usage` 에러. 플랜 한도 (주간/세션) 가 한 자릿수% 만 사용된 상태에서도 발생.

해결: claude.ai/settings/usage 우측 "추가 사용량" 스위치 ON + 월 지출 한도 설정. 자세한 진단/복구는 [troubleshooting A5](./troubleshooting.md#a5-out-of-extra-usage--openclaw-가-anthropic-응답-거부-claude-max-인데도).

---

## 4. SKILL.md — OpenClaw 의 작업 단위

가장 작은 SKILL.md:

```markdown
---
name: hello
description: "hello" 메시지에 "ok" 한 단어로 답한다. 본 스킬은 끝-끝 동작 검증용 데모.
---

# Hello (demo)

사용자 메시지가 정확히 `hello` 이면 `ok` 라고만 답하라. 그 외 메시지는 무시.
```

위치:

| 경로 | 용도 |
|---|---|
| `~/.openclaw/skills/<name>/SKILL.md` | managed — onboard 가 깐 것, 시스템 전역 |
| `<workspace>/skills/<name>/SKILL.md` | 워크스페이스 한정 |
| `<workspace>/.agents/<agent>/skills/<name>/SKILL.md` | 특정 에이전트 한정 |
| `~/.agents/<agent>/skills/<name>/SKILL.md` | 사용자 개인 에이전트 한정 |

스킬 디렉토리에 `scripts/`, `references/`, `assets/` 를 같이 두면 모델이 필요할 때 그것까지 가져다 쓴다.

---

## 5. 권한 / 안전장치 — OpenClaw 의 도구 정책

`~/.openclaw/openclaw.json` 의 `tools` / `browser` / `channels` 에서 deny 우선:

```json5
{
  channels: {
    telegram: {
      dmPolicy: "pairing",                  // 페어링 안 된 사용자 차단
      allowFrom: ["telegram:000000000"],    // 본인만
    },
  },
  browser: {
    ssrfPolicy: {
      dangerouslyAllowPrivateNetwork: false,
      hostnameAllowlist: [],                // 필요한 도메인만 화이트리스트
    },
  },
  hooks: {
    enabled: false,                         // 외부 webhook 수신은 기본 OFF
  },
  commands: {
    ownerAllowFrom: ["telegram:000000000"], // /diagnostics, /config 등 owner 권한
  },
}
```

전체 보안 베이스라인은 [`docs/07-openclaw-hardening.md`](./07-openclaw-hardening.md) §2 + §8 (초기 셋업 후 운영 하드닝 루틴).

---

## 6. 자주 깨지는 지점

- **인증 모드 혼동** — onboard 에서 BYOK 선택해놓고 `claude /login` 만 하면 OpenClaw 가 못 씀. `openclaw config get auth` 로 활성 모드 확인
- **위임 모드의 만료** — `claude` access token 8h. `openclaw doctor` 가 `Model auth: expired (0m)` 보고 → `claude /login` 또는 `claude setup-token`. ([troubleshooting A6](./troubleshooting.md#a6-no-credentials-found-for-profile-anthropicclaude-cli-실제로는-만료))
- **`openclaw models auth login` 함정** — 이 명령은 OpenClaw 프로필만 갱신, 실제 OAuth 트리거 X. 토큰은 `claude /login` 별도. ([troubleshooting A7](./troubleshooting.md#a7-openclaw-models-auth-login-을-해도-oauth-가-일어나지-않음))
- **`out of extra usage`** — 위임 모드의 추가 사용량 토글 OFF. ([troubleshooting A5](./troubleshooting.md#a5-out-of-extra-usage--openclaw-가-anthropic-응답-거부-claude-max-인데도))
- **스킬 미매칭** — `description:` 가 모호하면 모델이 스킬을 부르지 않음. "언제 사용하는지" 까지 명시
- **`gateway.host: "0.0.0.0"` 으로 자동 노출** — onboard 가 기본을 loopback 으로 두지만, 일부 가이드가 `0.0.0.0` 으로 바꾸도록 안내함. 변경하지 말 것 ([docs/07 §1](./07-openclaw-hardening.md#1-알려진-cve--취약점-인벤토리) reverse-proxy 우회 위험)
- **ClawHub 스킬 자동 설치** — 절대 자동화 금지. [docs/07 §4](./07-openclaw-hardening.md#4-스킬-clawhub-안전-정책) 의 리뷰 체크리스트 통과 후 수동 설치

---

## 7. 다음

- [02 — Claude CLI OAuth 위임](./02-claude-code-oauth.md) — 모드 B 사용 시 인증 절차
- [05 — Headless Ops](./05-headless-ops.md) — systemd 로 24/7 가동
- [07 — Hardening](./07-openclaw-hardening.md) — 운영 전 필독 (§8 초기 셋업 후 운영 하드닝 루틴 포함)
- [examples/hello-agent](../examples/hello-agent/) — 최소 SKILL.md 예제
- [recipes/auto-coding-loop](../recipes/auto-coding-loop.md) — 자율 코딩 루프

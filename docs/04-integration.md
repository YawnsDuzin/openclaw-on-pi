# 04 — Integration: OpenClaw 와 Claude Code 의 관계

> OpenClaw 는 **BYOK 자체 모델 라우팅** 으로 동작합니다. 본 가이드는 Anthropic Claude 를 1순위로 권장하지만 OpenClaw 가 Claude Code CLI 를 부르는 구조는 아닙니다. 두 도구가 같은 Pi 에 공존하지만 **다른 인증·다른 호출 경로** 입니다.

⚠ 검증 환경: OpenClaw ≥ 2026.2.6, Anthropic API key (BYOK), 선택적으로 Claude Code CLI.

> 📜 2026-05-16 재작성 라운드 — 1차 라운드는 "OpenClaw 가 코드 작성을 Claude Code 에 위임" 으로 잘못 가정했었음.

---

## 1. 책임 분리

| 도구 | 책임 |
|---|---|
| **OpenClaw** | 메시징 채널 라우팅 / 스킬 매칭 / BYOK 다중 모델 호출 / 도구 (셸·파일·브라우저·세션) / 자가 스킬 생성 |
| **SKILL.md** | 각 스킬의 정체와 동작. `~/.openclaw/skills/<name>/SKILL.md` (managed) 또는 workspace 하위 |
| **Claude Code CLI** | (선택) 사람이 직접 vibe-coding 할 때 별도 CLI 로 사용. OpenClaw 와 무관한 경로 |
| **CLAUDE.md** | Claude Code CLI 가 자동 로드하는 컨텍스트. **OpenClaw 와는 별개** — OpenClaw 는 SKILL.md 를 쓴다 |
| **settings.json** | Claude Code CLI 의 도구 권한. **OpenClaw 의 도구 정책은 `openclaw.json` 의 `tools` 키** |

---

## 2. OpenClaw 의 호출 경로 (실제 동작)

### 2-1. 메시지 수신 → 스킬 매칭

```
[Telegram bot] ── 메시지 "deploy staging" ──► [openclaw gateway :18789]
                                                     │
                                                     ▼
                                  스킬 메타 (XML 시스템 프롬프트) + 사용자 메시지
                                                     │
                                                     ▼
                                  BYOK 모델 (예: anthropic/claude-sonnet-4-6)
                                                     │
                                                     ▼
                                  도구 호출 (셸 / 파일 / 브라우저 / 세션)
                                                     │
                                                     ▼
                                  응답 → 같은 채널 thread 로 회신
```

스킬 매칭은 두 가지:

- **Auto**: SKILL.md 의 `description:` 이 시스템 프롬프트에 XML 로 주입 → 모델이 이름으로 호출
- **명시 슬래시 명령**: SKILL.md frontmatter 에 `user-invocable: true` 면 메시지가 `/skill-name` 으로 시작할 때 직접 디스패치

### 2-2. BYOK 라우팅

`~/.openclaw/openclaw.json` 의 `agents.defaults.model`:

```json5
{
  agents: {
    defaults: {
      model: {
        primary: "anthropic/claude-sonnet-4-6",
        fallbacks: [
          "anthropic/claude-opus-4-7",
          "openai/gpt-5-codex",
        ],
      },
    },
  },
}
```

OpenClaw 가 primary 호출 → rate limit / 5xx 시 자동 fallback. **Claude Code CLI 의 OAuth 와는 다른 자격증명** — 본 키는 console.anthropic.com 에서 발급한 API key.

---

## 3. Claude Code CLI 가 같이 있는 의미

| 상황 | 어느 도구 |
|---|---|
| Telegram 봇에 "이 PR 좀 봐줘" 라고 메시지 | **OpenClaw** — 자율 스킬이 PR 확인하고 응답 |
| 데스크탑/Pi 에서 직접 `claude -p "리팩터" --add-dir .` | **Claude Code CLI** — 본 가이드 [02](./02-claude-code-oauth.md) 로 OAuth |
| OpenClaw 의 cron 스킬이 새벽 3시에 자동 코드 정리 | **OpenClaw** — 본인의 BYOK Anthropic API key 로 모델 호출 |
| Pi 에 SSH 들어가서 사람이 `claude` 와 페어 프로그래밍 | **Claude Code CLI** |

두 인증이 한 Pi 에 공존:

```
~/.openclaw/openclaw.json      ← OpenClaw 의 Anthropic API key
~/.claude/credentials.json     ← Claude Code CLI 의 OAuth 토큰
```

> 💡 동일한 Anthropic 계정의 *구독* (Pro/Max) 은 Claude Code OAuth 에 묶여 있고, *API key* 는 별도 과금. OpenClaw 가 BYOK 로 API key 를 쓰면 별도 사용량이 부과된다. 본 가이드의 "구독으로 끝-끝 가동" 약속이 OpenClaw 본체에는 *부분* 만 적용 — Claude Code CLI 호출에는 구독, OpenClaw 의 자율 호출에는 API 과금이 필요할 수 있다.

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

OpenClaw `openclaw.json` 의 `tools` / `browser` / `channels` 에서 deny 우선 권장:

```json5
{
  channels: {
    telegram: {
      dmPolicy: "pairing",                  // 페어링 안 된 사용자 차단
      allowFrom: ["tg:000000000"],          // 본인만
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
}
```

전체 보안 베이스라인은 [docs/07-openclaw-hardening.md](./07-openclaw-hardening.md) §2.

---

## 6. 자주 깨지는 지점

- **두 인증 혼동** — OpenClaw 의 `agents.defaults.model` API key 와 `~/.claude/` OAuth 를 같은 줄 알고 헤맴
- **스킬 미매칭** — `description:` 가 모호하면 모델이 스킬을 부르지 않음. "언제 사용하는지" 까지 명시
- **`gateway.host: "0.0.0.0"` 으로 자동 노출** — onboard 가 기본을 loopback 으로 두지만, 일부 가이드가 `0.0.0.0` 으로 바꾸도록 안내함. 변경하지 말 것 (docs/07 §1 reverse-proxy 우회 위험)
- **ClawHub 스킬 자동 설치** — 절대 자동화 금지. [docs/07 §4](./07-openclaw-hardening.md#4-스킬-clawhub-안전-정책) 의 리뷰 체크리스트 통과 후 수동 설치

---

## 7. 다음

- [05 — Headless Ops](./05-headless-ops.md) — systemd 로 24/7 가동
- [07 — Hardening](./07-openclaw-hardening.md) — 운영 전 필독
- [examples/hello-agent](../examples/hello-agent/) — 최소 SKILL.md 예제
- [recipes/auto-coding-loop](../recipes/auto-coding-loop.md) — 자율 코딩 루프

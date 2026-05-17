# 08 — OpenClaw 설정 Reference

> `~/.openclaw/openclaw.json` (JSON5) 의 핵심 키 체계 + 본 가이드의 권장값 + 변경 방법.
>
> ⚠ 공식 reference 는 [docs.openclaw.ai/gateway/configuration](https://docs.openclaw.ai/gateway/configuration) (그리고 그 하위 페이지) 가 우선. 본 문서는 **2026-05-17 Pi 5 검증 시점의 권장 컨벤션** 이며 OpenClaw 릴리스마다 키 이름·기본값이 바뀔 수 있다. 공식 docs 와 충돌 시 공식 우선.

---

## 0. 파일 위치 · 형식 · 변경 방법

### 0-1. 파일 위치

- **user 모드 (권장)**: `~/.openclaw/openclaw.json`
- **system 모드** ([docs/05 §2-1](./05-headless-ops.md#2-1-시스템-모드-사전-준비)): `/opt/openclaw/.openclaw/openclaw.json` (또는 `/etc/openclaw/openclaw.json` — onboard 가 정한 경로)

### 0-2. 형식

**JSON5** — JSON 위에 다음이 허용:

- 주석 (`//` 한 줄, `/* */` 블록)
- 트레일링 콤마 (`{a: 1,}`)
- 따옴표 없는 키 (`{ a: 1 }` 가능)
- 작은따옴표 (`{a: 'x'}` 가능)

> 💡 직접 편집 시 JSON 으로 작성해도 OpenClaw 가 같이 파싱한다. JSON5 의 편의는 주석/콤마 정도가 가장 유용.

### 0-3. 변경 방법 — 세 가지

| 방법 | 언제 |
|---|---|
| `openclaw onboard --install-daemon` | 최초 1회 — 대화형 마법사가 핵심 키를 묻고 파일 생성 |
| `openclaw configure` | 재구성 — 인증 모드 / 모델 / 채널을 다시 묻고 갱신 |
| `openclaw config get <key>` / `set <key> <value>` | 개별 키 단위 변경 (예: `openclaw config set channels.telegram.enabled true`) |
| 직접 편집 (`vim ~/.openclaw/openclaw.json`) | 표 변경 / 주석 추가 / 복합 변경 시. 변경 후 `systemctl --user restart openclaw` 으로 반영 |

> ⚠ `config set` 은 *원자적* (lock 사용). 직접 편집 + restart 경로는 lock 충돌 가능 — gateway 가 멈춰 있을 때만 안전.

### 0-4. 변경 검증

```bash
# JSON5 문법 점검 (jq 는 JSON5 미지원, JSON 변환 도구 필요. 가장 단순한 점검:)
openclaw config validate            # 또는 openclaw doctor

# 활성 인증 모드 / 모델 확인
openclaw config get agents.defaults.agentRuntime
openclaw config get agents.defaults.model.primary
openclaw config get auth.profiles
```

---

## 1. `agents` — 에이전트 정의 / 인증 모드 / 모델 라우팅

### 1-1. 구조

```json5
{
  agents: {
    defaults: { /* 모든 에이전트 공통 */ },
    list: [    /* 명명된 다중 에이전트 (선택) */ ],
  },
}
```

### 1-2. `agents.defaults`

| 키 | 의미 | 본 가이드 권장값 |
|---|---|---|
| `agentRuntime.id` | 인증/호출 백엔드 | 모드 (A): `"anthropic-api"` (또는 `"openai-api"`, `"google-api"`) / 모드 (B): `"claude-cli"` |
| `model.primary` | 1순위 모델 (`provider/model-id`) | 모드 (A): `"anthropic/claude-sonnet-4-6"` / 모드 (B): `"anthropic/claude-haiku-4-5"` (CLI 빌링 풀 절약) |
| `model.fallbacks` | rate-limit / 5xx 시 차순위 | `["anthropic/claude-opus-4-7", "openai/gpt-5-codex"]` 식 |
| `workspace` | 작업 디렉토리 | `"~/.openclaw/workspace"` (기본) |
| `skills` | 사용 가능 스킬 화이트리스트. 빈 배열이면 `~/.openclaw/skills/*` 전체 허용 | 첫 1주는 명시 화이트리스트로 (예: `["hello", "log-triage"]`) |
| `timeoutSeconds` | 1회 호출 타임아웃 | `600` (10분) — Pi 환경 권장 |
| `concurrency` | 동시 작업 수 | Pi 4 4GB → `1`, Pi 5 8GB → `2` |
| `thinking` | Claude extended thinking 레벨 | `"auto"` (모델이 결정). 코드 리뷰 / 복잡 분석은 `"high"` |

### 1-3. `agents.list[]` — 다중 에이전트

역할별 분리 ([recipes/multi-agent-orchestration](../recipes/multi-agent-orchestration.md)):

```json5
{
  agents: {
    defaults: { workspace: "~/.openclaw/workspace" },
    list: [
      {
        name: "triage",
        model: { primary: "anthropic/claude-haiku-4-5" },
        skills: ["log-triage", "issue-categorize"],
      },
      {
        name: "coder",
        model: {
          primary: "anthropic/claude-sonnet-4-6",
          fallbacks: ["anthropic/claude-opus-4-7"],
        },
        skills: ["cleanup-issue", "review-pr"],
      },
    ],
  },
}
```

`channels.<channel>.routing[]` 으로 어느 에이전트가 어떤 메시지를 받을지 분리 (§3-3 참고).

---

## 2. `auth.profiles` — 인증 자격증명 프로필

OpenClaw 의 두 인증 모드에 대응 ([04 §1](./04-integration.md#1-두-인증-모드)).

### 2-1. 모드 (A) — BYOK API key

```json5
{
  auth: {
    profiles: {
      "anthropic:api-key": {
        provider: "anthropic-api",
        mode: "api-key",
        // API key 는 ENV 로 주입 — 본 파일에는 절대 평문 금지
        // (OpenClaw 가 env ANTHROPIC_API_KEY 자동 인입)
      },
    },
  },
}
```

env 주입 (systemd `EnvironmentFile` 또는 `~/.openclaw-secrets/env`):

```bash
ANTHROPIC_API_KEY=sk-ant-...
```

### 2-2. 모드 (B) — Claude CLI 위임 OAuth

```json5
{
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

- 자격증명 발급: [docs/02 §2](./02-claude-code-oauth.md#2-표준-절차--claude-login) 또는 무인 운영 시 [§3](./02-claude-code-oauth.md#3-무인-운영--claude-setup-token-장기-토큰-강력-권장)
- 만료 진단: `openclaw doctor 2>&1 | grep 'Model auth'`

---

## 3. `gateway` — 게이트웨이 서버 설정

### 3-1. 네트워크 바인딩

```json5
{
  gateway: {
    host: "127.0.0.1",      // 바인딩 IP
    port: 18789,            // 포트
    bind: "loopback",       // 정책: loopback | auto | lan | tailnet | custom
  },
}
```

| `bind` 값 | 의미 | 본 가이드 권장? |
|---|---|---|
| `"loopback"` | 127.0.0.1 만 | ✅ **기본 강제** |
| `"auto"` | 자동 선택 (보통 loopback 또는 LAN) | ❌ |
| `"lan"` | LAN IP 까지 | ❌ — reverse proxy 인증 우회 위험 |
| `"tailnet"` | Tailscale 메시만 | ⚠ Tailscale ACL 같이 운영 시만 |
| `"custom"` | `host` 의 값을 그대로 | ⚠ 외부 노출 시 docs/07 §3 절차 필수 |

> 🚨 `host: "0.0.0.0"` + `bind: "auto"` 조합은 공개 노출 인스턴스의 ~93.4% 인증 우회 (CVE-2026-25253 + reverse proxy 우회). [docs/07 §1](./07-openclaw-hardening.md#1-알려진-cve--취약점-인벤토리).

### 3-2. 인증 (`gateway.auth`)

```json5
{
  gateway: {
    auth: {
      mode: "token",                                    // token | trusted-proxy
      token: "REPLACE_VIA_ENV:OPENCLAW_GATEWAY_TOKEN",  // env 주입
      allowTailscale: false,                            // tailnet 사용 시만 true
      rateLimit: {
        maxAttempts: 10,
        windowMs: 60000,                                // 60s 윈도우
        exemptLoopback: true,                           // loopback 호출은 한도 면제
      },
    },
  },
}
```

| `mode` | 의미 |
|---|---|
| `"token"` | API 토큰 헤더 (`Authorization: Bearer <token>`) — 본 가이드 권장 |
| `"trusted-proxy"` | identity-aware reverse proxy (Cloudflare Access / oauth2-proxy 등) 가 인증 책임. `trustedProxy.userHeader` 로 user 정보 인입 |

### 3-3. Reverse Proxy 화이트리스트

```json5
{
  gateway: {
    trustedProxies: ["10.0.0.5"],   // proxy 의 *고정* 사설 IP
  },
}
```

- 비어 있어야 안전 — proxy 없으면 무조건 빈 배열
- proxy 뒤에 둘 거면 [docs/07 §3](./07-openclaw-hardening.md#3-외부-노출이-필요한-경우--reverse-proxy-안전-절차) 따라 IP / mTLS / 외부 inbound 차단까지 완비

---

## 4. `channels` — 메시징 채널

### 4-1. 공통 키

모든 채널 (`telegram` / `discord` / `slack` / `whatsapp` / `signal` / `imessage` / ...) 이 공유:

| 키 | 의미 |
|---|---|
| `enabled` | true/false. 페어링 검증 전까지 false 유지 권장 |
| `botToken` (또는 채널별 토큰) | env 주입 권장 |
| `dmPolicy` | `"pairing"` (페어링 안 된 사용자 차단) / `"open"` (누구나) / `"closed"` (DM 비활성) |
| `allowFrom` | user id 화이트리스트 (예: `["telegram:000000000"]`) |
| `rateLimit.perUser` | 사용자당 분당 메시지 한도 |
| `routing[]` | 메시지 패턴 → 에이전트 매칭 (§3-3 참고) |

### 4-2. Telegram 예제

```json5
{
  channels: {
    telegram: {
      enabled: true,
      botToken: "REPLACE_VIA_ENV:TELEGRAM_BOT_TOKEN",
      dmPolicy: "pairing",
      allowFrom: ["telegram:000000000"],     // 본인 user id (페어링 후 자동 등록)
      rateLimit: { perUser: 30 },            // 분당 30 메시지
    },
  },
}
```

봇 만들기 + 페어링 절차: [docs/03 §5](./03-openclaw-install.md#5-메시징-채널-연결--telegram-예시).

### 4-3. 라우팅 — 슬래시 명령으로 에이전트 분리

```json5
{
  channels: {
    telegram: {
      // ...
      routing: [
        { match: "^/triage", agent: "triage" },
        { match: "^/code",   agent: "coder" },
        { default: true,     agent: "triage" },   // 매칭 없으면 가벼운 모델
      ],
    },
  },
}
```

### 4-4. 기타 채널 — Discord / Slack / WhatsApp

각자 다른 페어링 절차 + 추가 의존성. 본 가이드 첫 가동은 Telegram 1개 권장. 추가 채널 활성화 전 [docs/07 §6](./07-openclaw-hardening.md#6-prompt-injection-운영-완화) 의 prompt injection 운영 완화 확인.

### 4-5. 소유자 권한 (`commands.ownerAllowFrom`)

`/diagnostics`, `/config get/set`, `/skill install` 같은 owner 권한 명령은 별도 화이트리스트:

```json5
{
  commands: {
    ownerAllowFrom: ["telegram:000000000"],   // 본 가이드 권장 — 본인만
  },
}
```

---

## 5. `session` / `messages` — 세션 · 응답 정책

```json5
{
  session: {
    defaultScope: "channel",     // channel | user | thread
    historyLimit: 50,             // 보존할 메시지 수
    idleTimeout: 3600,            // 비활성 세션 종료 (초)
  },
  messages: {
    replyVisibility: "thread",    // thread | dm | all
    mentionPolicy: "mention",     // mention (멘션 시만 응답) | always (모든 메시지)
  },
}
```

| 키 | 권장 |
|---|---|
| `defaultScope` | `"channel"` — 같은 채널 대화 이어짐. 가족 공용이면 `"user"` 로 격리 |
| `replyVisibility` | `"thread"` — 그룹 채팅 시 스레드로 답장 (방해 최소) |
| `mentionPolicy` | `"mention"` — 봇 멘션 또는 슬래시 명령 시만 응답 (그룹 채팅 노이즈 방지) |

---

## 6. `tools` — 자율 도구 정책

OpenClaw 의 자율 셸 실행 / 파일 R/W / 브라우저 / 세션 도구를 모델이 호출할 때 적용되는 정책.

```json5
{
  tools: {
    skills: {
      virusTotalScan: true,                  // ClawHub 스킬 자동 VT 스캔 (v2026.2.6+)
      codeSafetyScanner: true,               // 정적 분석
      autoInstall: false,                    // ⚠ ClawHub 외부 스킬 자동 설치 금지
    },
    shell: {
      // 셸 실행 deny 우선 (실제 키 이름은 OpenClaw 버전 확인)
      policy: {
        deny: ["rm -rf:*", "sudo:*", "curl:*", "wget:*"],
        allow: [],                           // 필요한 명령만
      },
    },
    file: {
      readOnlyPaths: ["/etc", "/var/log"],   // 읽기만
      denyPaths: ["~/.ssh", "~/.openclaw"],  // 절대 접근 금지
    },
  },
}
```

> ⚠ 본 절의 정확한 키 이름은 OpenClaw 버전마다 다를 수 있다. `openclaw config get tools` 로 현재 활성 키 구조 확인 후 본 가이드 권장값 적용. 핵심 원칙: **deny 우선 + allow 화이트리스트**.

---

## 7. `cron` — 정기 작업

```json5
{
  cron: {
    enabled: true,
    jobs: [
      {
        schedule: "5 * * * *",               // 매시 5분
        skill: "log-triage",
        env: { LOG_TRIAGE_PUBLISH: "stdout" },  // 잡별 env 오버라이드
      },
      {
        schedule: "0 */6 * * *",             // 6시간마다
        skill: "cleanup-issue",
        agent: "coder",                      // 특정 에이전트로 실행
        env: { PR_BOT_REPO: "youruser/yourrepo" },
      },
    ],
  },
}
```

cron 표현식은 표준 5필드 (`분 시 일 월 요일`). 정확한 실행 위치 (OpenClaw 내장 vs systemd timer) 선택은 [recipes/scheduled-agent-tasks](../recipes/scheduled-agent-tasks.md) 참고.

---

## 8. `hooks` — 외부 webhook 수신

```json5
{
  hooks: {
    enabled: false,                          // 기본 OFF — 외부 trigger 가 정말 필요할 때만 ON
    token: "REPLACE_VIA_ENV:OPENCLAW_HOOKS_TOKEN",  // gateway.auth.token 과 *다른* 별도 토큰
    allowRequestSessionKey: false,           // 외부 webhook 이 세션키 임의 지정 허용? 보통 false
    allowedSessionKeyPrefixes: ["hook:"],    // 허용 시 prefix 화이트리스트
    endpoints: [
      // 외부에서 POST /hook/<id> 로 호출 시 매칭
      // { path: "/github/issue", skill: "github-issue-triage" },
    ],
  },
}
```

> 🚨 hooks 는 외부 inbound 면이라 가장 위험. 활성화 전 [docs/07 §3](./07-openclaw-hardening.md#3-외부-노출이-필요한-경우--reverse-proxy-안전-절차) 의 reverse proxy 절차 + 토큰 회전 정책 필수.

---

## 9. `browser` — 자동 브라우저 SSRF 보호

```json5
{
  browser: {
    ssrfPolicy: {
      dangerouslyAllowPrivateNetwork: false, // ⚠ 절대 true 금지 (사내망 noscan)
      hostnameAllowlist: [                   // 명시 도메인만 허용
        "*.github.com",
        "api.anthropic.com",
      ],
      blockMetadataEndpoints: true,          // AWS/GCP 메타데이터 (169.254.169.254 등) 차단
    },
    userAgent: "OpenClaw/2026.x (+pi)",
    timeoutSeconds: 30,
  },
}
```

> Prompt injection 으로 모델이 임의 URL 을 fetch 하게 유도될 수 있음. SSRF 보호가 깨지면 사내 메타데이터 / 다른 호스트 / 로컬 서비스를 노출 → [docs/07 §6](./07-openclaw-hardening.md#6-prompt-injection-운영-완화).

---

## 10. `env` — 환경변수 인입

```json5
{
  env: {
    // OpenClaw 가 부팅 시 자동으로 인입할 env 키 목록.
    // 값은 절대 본 파일에 적지 말고 systemd EnvironmentFile 또는 OS env 로 주입.
    inject: [
      "ANTHROPIC_API_KEY",         // BYOK 모드
      "OPENCLAW_GATEWAY_TOKEN",    // gateway.auth.token
      "OPENCLAW_HOOKS_TOKEN",      // hooks.token
      "TELEGRAM_BOT_TOKEN",        // channels.telegram.botToken
      "GITHUB_TOKEN",              // examples/github-pr-bot
      "NTFY_TOPIC",                // examples/log-triage
    ],
  },
}
```

권장 env 보관 위치:

```bash
~/.openclaw-secrets/env      # 권한 600, .gitignore 에 제외
```

systemd 유닛에서 `EnvironmentFile=-/home/dzp/.openclaw-secrets/env` (선두 `-` 는 파일 부재 시 무시).

---

## 11. `logging` — 로그 레벨 / 출력

```json5
{
  logging: {
    level: "info",               // debug | info | warn | error
    output: "journal",           // journal | file:/path/to/log | stdout
    redactSecrets: true,         // 토큰 / API key 패턴 자동 마스킹
    sessions: {
      keepDays: 14,
    },
  },
}
```

- 첫 1주는 `level: "debug"` 권장 (디버깅 편의), 안정화 후 `"info"`
- `redactSecrets: true` 는 절대 꺼두지 말 것

---

## 12. `ui` — TUI / 색상

`openclaw tui` 의 외형 설정. 가동에 영향 X.

```json5
{
  ui: {
    theme: "dark",               // dark | light | auto
    showTimestamps: true,
  },
}
```

---

## 13. 트러블슈팅 — 설정 변경 후 안 먹힐 때

| 증상 | 원인 / 해결 |
|---|---|
| `config set` 직후 변경 안 됨 | gateway 가 메모리 캐시 유지. `systemctl --user restart openclaw` |
| 직접 편집 후 OpenClaw 안 뜸 | JSON5 문법 오류 — `openclaw config validate` |
| `agentRuntime` 바꿨는데 옛 모드로 호출 | `~/.openclaw/state.json` 의 active profile cache. `openclaw configure` 재실행 |
| token env 주입 안 됨 | systemd `EnvironmentFile` 의 선두 `-` 누락 / 파일 권한 600 아님 |
| 스킬이 매칭 안 됨 | `agents.defaults.skills` 화이트리스트에서 빠짐. 또는 `~/.openclaw/skills/<name>/SKILL.md` 자체 없음 |
| reverse proxy 뒤에서 인증 우회 | `trustedProxies` 미설정. [docs/07 §3](./07-openclaw-hardening.md#3-외부-노출이-필요한-경우--reverse-proxy-안전-절차) |

---

## 14. 외부 참조

- [공식 docs.openclaw.ai/gateway/configuration](https://docs.openclaw.ai/gateway/configuration) — 모든 키의 최신 정의
- [공식 docs.openclaw.ai/concepts/oauth](https://docs.openclaw.ai/concepts/oauth) — Claude CLI 위임 모드 동작 원리
- [clawdocs.org/security/known-vulnerabilities](https://clawdocs.org/security/known-vulnerabilities/) — CVE 인벤토리 + 보안 권장 설정
- [docs/07-openclaw-hardening.md](./07-openclaw-hardening.md) — 본 가이드의 보안 베이스라인
- [docs/04-integration.md §1](./04-integration.md#1-두-인증-모드) — 두 인증 모드 비교

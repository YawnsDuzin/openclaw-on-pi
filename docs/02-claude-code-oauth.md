# 02 — Claude CLI OAuth (OpenClaw 가 위임 사용)

> OpenClaw 의 **모델 호출을 Claude Code CLI 의 OAuth 로 위임**하는 모드의 인증 가이드.
> Claude Pro/Max 구독으로 OpenClaw 를 굴릴 때만 본 챕터 필요. API key (BYOK) 모드면 스킵.

> 📌 **본 챕터의 정체**: Claude Code CLI 자체는 본 저장소의 주제가 아니다. 다만 OpenClaw 가 `agentRuntime.id: "claude-cli"` 모드일 때 **로컬 `claude` CLI 를 서브프로세스로 띄워 그쪽의 OAuth 를 통해 Anthropic 을 호출**한다 ([OpenClaw 공식 docs/concepts/oauth](https://docs.openclaw.ai/concepts/oauth) 에서 sanctioned 모드로 명시 — *"Anthropic staff told us this usage is allowed again"*). 따라서 claude CLI 의 OAuth 가 죽으면 OpenClaw 도 같이 멈춘다. 그래서 본 가이드에 한 챕터.

⚠ 검증 환경: Claude Code CLI 2.1.x (`@anthropic-ai/claude-code` npm) + OpenClaw 2026.5.x. 2026-05-17 Pi 5 (8GB) 에서 onboard → `claude /login` → `openclaw tui` 응답까지 확인.

---

## 1. 두 인증 모드 — 어느 쪽?

OpenClaw `onboard` 마법사가 묻는다:

| 모드 | 장점 | 단점 | 본 챕터 |
|---|---|---|---|
| **Anthropic API key** (BYOK) | 종량 과금, 만료 관리 단순 | 별도 결제 등록, 구독과 별개 청구 | 불필요 |
| **Anthropic Claude CLI** (OAuth 위임) | 기존 Pro/Max 구독 그대로 활용 | access token 8h 만료, 사람 개입 가능성 | **필수** |

권장:

- **무인 24/7 운영** + Pro/Max 구독자: **OAuth 위임 + `claude setup-token` (장기 토큰)** — 본 챕터 §3
- **API 종량 과금이 더 편함**: BYOK 로 가고 본 챕터 스킵

---

## 2. 표준 절차 — `claude /login`

Pi 에 직접 키보드/모니터가 없으면 SSH 로 들어가서 진행. `claude` CLI 가 화면에 표시하는 OAuth URL 을 로컬 PC 브라우저로 따라가는 흐름.

### 2-1. Pi 에 SSH 접속

```bash
ssh dzp@<pi-host>
```

### 2-2. `claude` TUI 열고 `/login`

```bash
claude                          # Claude TUI 열림
# TUI 안에서:
/login                          # OAuth 플로우 시작
```

화면에 URL 출력:

```
Open this URL in your browser:
  https://console.anthropic.com/oauth/authorize?...&redirect_uri=...
```

### 2-3. 로컬 PC 브라우저로 URL 열기

위 URL 을 그대로 복사해서 노트북/PC 브라우저에 붙여넣기. Anthropic 로그인 → 동의 → 받은 코드 / 토큰을 Pi 의 Claude TUI 에 붙여넣기.

> 💡 Claude Code 2.1.x 는 콜백 URL 이 아닌 **코드 입력 모드** 를 지원해서 SSH `-L` 역포트포워딩 불필요. 구버전을 쓴다면 [`scripts/oauth-tunnel.sh`](../scripts/oauth-tunnel.sh) 가 SSH 터널 절차 안내.

### 2-4. 성공 확인

TUI 안에서:

```
✓ Logged in as <email>.
```

`/exit` 또는 Ctrl+C 두 번으로 TUI 빠져나오기. 토큰은 `~/.claude/.credentials.json` (모드 600) 에 저장됨.

### 2-5. OpenClaw 가 새 토큰을 보는지 확인

```bash
openclaw doctor 2>&1 | grep -A3 'Model auth'
```

기대 출력:

```
- anthropic:claude-cli: expiring (8h) — ...
```

`expired (0m)` 이면 위 절차 재시도. `valid` / `expiring (Nh)` 이면 OK.

---

## 3. 무인 운영 — `claude setup-token` (장기 토큰, 강력 권장)

§2 의 OAuth access token 은 ≈ **8 시간 TTL**. 자동 refresh 가 실패하는 케이스가 관찰됨 → 사람이 매 8 시간마다 `claude /login` 해야 하는 운영 부담.

해결: Claude Code CLI 의 **장기 토큰 모드**:

```bash
claude setup-token              # 일회성 인터랙티브, Claude 구독 필요
```

> *"Set up a long-lived authentication token (requires Claude subscription)"* — `claude --help` 발췌

- access/refresh 토큰 사이클을 우회 → 8h TTL 문제 사라짐
- `~/.claude/` 하위에 저장, OpenClaw 가 그대로 위임 사용
- 분실/회수까지 유효 (사실상 만료 없음)

이 모드면 §4 의 만료 관리가 의미 없어진다 (헬스체크의 60일 mtime 경고만 monitoring).

> ⚠ 보안 트레이드오프: 장기 토큰은 분실 영향이 크다. 침해 가정 대응 ([07 §5-4](./07-openclaw-hardening.md#5-자격증명-보호-openclaw-평문-저장-대응)) 에 claude 토큰 회수 절차 포함시킬 것.

---

## 4. 토큰 만료 / 재인증 (§3 안 쓸 때)

### 4-1. TTL 사실

- access token TTL ≈ 8 시간. refresh token 은 장기 유효.
- OpenClaw 공식 docs 는 만료 시 자동 refresh 한다고 명시하나 **실 운영에서 실패 케이스 관찰됨** — `No credentials found for profile "anthropic:claude-cli"` 로 fall-through. 본 가이드는 8h 만료를 가정하고 설계 권장.
- 헬스체크 (`scripts/healthcheck.sh`) 가 토큰 파일 mtime 으로 나이 추적 (기본 60일 경과 시 경고).

### 4-2. 진단

```bash
openclaw doctor 2>&1 | grep -A3 'Model auth'
```

- `valid` / `expiring (Nh)` → OK, N 시간 후 만료
- `expired (0m)` → 즉시 재인증 필요

### 4-3. 재인증

§2 의 `claude /login` 절차 재실행. 기존 자격증명을 백업한 뒤:

```bash
mv ~/.claude/.credentials.json ~/.claude/.credentials.json.bak.$(date +%s)
claude                          # TUI → /login
```

---

## 5. 트러블슈팅

| 증상 | 원인 / 해결 |
|---|---|
| `claude /login` 의 콜백이 안 옴 | 2.1.x 코드 입력 모드 사용. 구버전이면 SSH `-L` 으로 포트포워딩 필요 ([troubleshooting A1](./troubleshooting.md#a1-claude-login-후에도-콜백이-안-옴)) |
| `clock skew` / `token signature invalid` | NTP 동기화 안 됨. `timedatectl set-ntp true` |
| `No credentials found for profile "anthropic:claude-cli"` (OpenClaw) | 실제로는 만료. `openclaw doctor` 로 확인 후 §4-3 재인증. [troubleshooting A6](./troubleshooting.md#a6-no-credentials-found-for-profile-anthropicclaude-cli-실제로는-만료) |
| `openclaw models auth login` 했는데 OAuth URL 이 안 뜸 | 그 명령은 OpenClaw 프로필만 갱신. 토큰은 `claude /login` 별도 필요. [troubleshooting A7](./troubleshooting.md#a7-openclaw-models-auth-login-을-해도-oauth-가-일어나지-않음) |
| `out of extra usage` (Max 구독 인데도) | claude.ai/settings/usage 의 "추가 사용량" 토글 OFF. [troubleshooting A5](./troubleshooting.md#a5-out-of-extra-usage--openclaw-가-anthropic-응답-거부-claude-max-인데도) |
| 디스크 가득 → 토큰 갱신 쓰기 실패 | `df -h ~` 확인 후 정리 |
| 재인증 후에도 401 | 옛 자격증명 남음. `~/.claude/.credentials*` 모두 백업 후 재시도 |

---

## 6. 보안

- `~/.claude/.credentials.json` 은 **OAuth 토큰 (또는 장기 토큰)** 을 담는다. 절대 git 커밋 금지. 본 저장소 `.gitignore` 에 제외 패턴 포함.
- 백업 시 [`age`](https://github.com/FiloSottile/age) 등으로 암호화:

  ```bash
  age -p ~/.claude/.credentials.json -o ~/credentials.json.age
  ```

- 권한 강제: `chmod 700 ~/.claude && chmod 600 ~/.claude/.credentials.json` (OpenClaw `security audit --fix` 가 자동으로 잡음)
- Pi 침해 가정 시: `claude` 토큰 즉시 회수 (Anthropic 콘솔에서 device revoke) + 본 가이드 [07 §5-4](./07-openclaw-hardening.md#5-자격증명-보호-openclaw-평문-저장-대응) 의 사고 체크리스트.

---

## 다음

- [03 — OpenClaw 설치](./03-openclaw-install.md)
- [05 — 헤드리스 운영](./05-headless-ops.md)
- [07 — OpenClaw Hardening](./07-openclaw-hardening.md)

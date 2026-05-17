# 02 — Claude Code OAuth (헤드리스 인증)

> 브라우저가 없는 Pi 에서 **Claude Code CLI** 의 OAuth 인증을 받는 방법. 본 가이드의 OpenClaw 운영에도 직접 영향이 있는 챕터.

> 📌 **OpenClaw 와의 관계** (1차 라운드 가정 정정): OpenClaw 는 BYOK API key 도 지원하지만, **로컬 Claude Code CLI 의 OAuth 를 위임 사용**할 수도 있다 (`agentRuntime.id: "claude-cli"` 모드). 이 모드를 쓰면 본 절차의 `claude /login` 이 OpenClaw 의 모델 호출에도 직접 영향을 준다 — claude CLI 의 access token 이 만료되면 OpenClaw 도 `No credentials found for profile "anthropic:claude-cli"` 로 실패. (이 사용은 [OpenClaw 공식 docs/concepts/oauth](https://docs.openclaw.ai/concepts/oauth) 에서 sanctioned 모드로 명시 — *"Anthropic staff told us this usage is allowed again"*.) 무인 운영이라면 [§5](#5-무인-운영--장기-토큰) 의 `claude setup-token` 사용 권장.
>
> ⚠ Claude OAuth 구독으로 routing 시 추가 함정: `claude -p` (programmatic) 경로는 **"추가 사용량" 풀에서 빌링**되므로, 잔액 있어도 claude.ai 의 토글이 OFF 면 거부 — [troubleshooting A5](./troubleshooting.md#a5-out-of-extra-usage--openclaw-가-anthropic-응답-거부-claude-max-인데도) 참조.

⚠ 검증 환경: Claude Code CLI (npm `@anthropic-ai/claude-code`) 안정 버전 기준. 향후 CLI 가 디바이스 코드 플로우(device code flow) 를 추가하면 본 문서의 "SSH 역포트포워딩 트릭" 은 불필요해진다.

---

## 1. 본질 — 왜 트릭이 필요한가

Claude Code 의 `claude login` 은 OAuth 2.0 Authorization Code + PKCE 플로우를 사용한다.
브라우저가 Anthropic 콘솔에서 사용자 동의를 받은 뒤 **`http://localhost:<port>/callback?code=...`** 으로 리다이렉트하는데, Pi 가 헤드리스라면:

- Pi 안에 브라우저가 없다 → URL 을 열 수 없다
- 로컬 PC 브라우저로 URL 을 열어도 → 콜백이 **로컬 PC 의 localhost** 로 가버려 Pi 에 도달 못 함

해결: **SSH 역포트포워딩**(`ssh -L`) 으로 로컬 PC 의 `localhost:<port>` → Pi 의 `localhost:<port>` 를 잇는다. 이러면 브라우저가 콜백을 보내도 SSH 터널을 타고 Pi 의 `claude` 프로세스가 받게 된다.

---

## 2. 절차 (요약)

본 저장소의 [`scripts/oauth-tunnel.sh`](../scripts/oauth-tunnel.sh) 가 안내문을 출력해준다. 핵심만 옮기면:

### 2-1. 로컬 PC 에서 SSH 세션 열기

```bash
# 로컬 PC 의 터미널에서
ssh -L 54545:localhost:54545 pi@<pi-host>
```

`-L LPORT:HOST:RPORT` 는 "로컬의 LPORT 로 들어온 트래픽을 SSH 서버측의 HOST:RPORT 로 전달". 여기서 HOST 는 SSH 서버(=Pi) 의 시점이므로 `localhost` 는 Pi 자신이다.

### 2-2. Pi 안에서 안내 출력 (선택)

```bash
bash scripts/oauth-tunnel.sh
# 또는 다른 포트:
bash scripts/oauth-tunnel.sh 55656
```

포트를 바꿨다면 SSH `-L` 도 같은 포트로 다시 열어야 한다.

### 2-3. claude /login (TUI) 또는 claude login (shell)

**권장 — Claude Code 2.1.x 의 슬래시 명령**:

```bash
claude                   # TUI 열기
# TUI 안에서 입력:
/login
```

또는 셸에서 직접 (구버전 호환):

```bash
claude login
```

두 방식 모두 다음 형태로 URL 이 출력된다:

```
Open this URL in your browser:
  https://console.anthropic.com/oauth/authorize?...&redirect_uri=http%3A%2F%2Flocalhost%3A54545%2Fcallback&...
```

> ⚠ `openclaw models auth login --provider anthropic` 은 OAuth 플로우를 트리거하지 않는다 — OpenClaw 의 auth 프로필 메타만 갱신. 실제 토큰 갱신은 위 `claude /login` 절차로만 가능. ([troubleshooting A7](./troubleshooting.md#a7-openclaw-models-auth-login-을-해도-oauth-가-일어나지-않음))

### 2-4. 로컬 PC 브라우저로 URL 열기

위 URL 을 그대로 복사해서 로컬 PC 브라우저에 붙여넣기. Anthropic 로그인 → 동의 → `localhost:54545/callback?code=...` 로 리다이렉트.

이 시점에 SSH 터널을 타고 콜백이 Pi 에 도달하면 `claude login` 이 자동 종료되고 다음 메시지가 뜬다:

```
Logged in as <email>.
Credentials saved to ~/.claude/credentials.json
```

### 2-5. 권한 설정

```bash
chmod 700 ~/.claude
chmod 600 ~/.claude/credentials.json
```

---

## 3. 확인

```bash
# 인증 상태
claude --help        # 정상 출력
ls -la ~/.claude/credentials.json

# 가벼운 호출 (구독 한도 안 씀, 모델 응답 1줄)
claude -p "say 'ok' and nothing else"
```

---

## 4. 토큰 만료 / 재인증

### 4-1. 토큰 TTL

- OAuth access token TTL ≈ **8 시간**. 리프레시 토큰은 장기 유효 (수 주~수 개월).
- 문서상으로는 access token 만료 시 리프레시 토큰으로 자동 갱신되어야 함.
- **하지만 실 운영에서 자동 갱신이 실패하는 케이스 관찰됨** — OpenClaw 가 위임 사용하는 모드에서 "No credentials found for profile" 으로 fall-through. 본 가이드는 8h 만료를 가정하고 운영 설계하는 것을 권장.
- 헬스체크가 토큰 파일 mtime 으로 나이를 추적한다 ([`scripts/healthcheck.sh`](../scripts/healthcheck.sh), 기본 60일 경과 시 경고).

### 4-2. 진단

```bash
openclaw doctor 2>&1 | grep -A3 'Model auth'
```

- `valid` / `expiring (Nh)` → OK, N 시간 후 만료
- `expired (0m)` → 즉시 재인증 필요

### 4-3. 재인증 (수동)

기존 자격증명을 백업한 뒤 [§2-3](#2-3-claude-login-tui-또는-claude-login-shell) 의 `claude /login` 절차:

```bash
mv ~/.claude/.credentials.json ~/.claude/.credentials.json.bak.$(date +%s)
bash scripts/oauth-tunnel.sh   # SSH 터널 안내 (선택)
claude                          # TUI → /login
```

---

## 5. 무인 운영 — 장기 토큰

24/7 Pi 무인 운영에서 사람이 매 8 시간마다 `claude /login` 하는 건 비현실. Claude Code CLI 의 **장기 토큰 모드**가 정답:

```bash
claude setup-token
```

> "Set up a long-lived authentication token (requires Claude subscription)" — `claude --help` 발췌

- 일회성 인터랙티브 절차 (구독 계정으로 로그인하여 장기 토큰 발급)
- access/refresh 토큰 사이클을 우회 → 8h TTL 문제 사라짐
- `~/.claude/` 하위에 저장되고 OpenClaw 가 그대로 위임 사용 가능
- 분실/회수까지 유효

이 모드를 쓰면 [§4](#4-토큰-만료--재인증) 의 만료 관리는 더 이상 필요 없다 (헬스체크의 60일 경고만 monitoring 으로 유지).

> 💡 보안 트레이드오프: 장기 토큰은 분실 시 영향이 크다. Pi 침해 가정 대응 ([07 §5-4](./07-openclaw-hardening.md#5-자격증명-보호-openclaw-평문-저장-대응)) 에서 `claude` 토큰 회수 절차도 포함시킬 것.

**대안**: Anthropic API key (`ANTHROPIC_API_KEY`) — 구독과 완전 분리, 종량 과금. OpenClaw 설정 변경:

```bash
openclaw configure       # 재실행하여 "Anthropic API key" 선택
```

---

## 6. 트러블슈팅

| 증상 | 원인 / 해결 |
|---|---|
| `Address already in use` (로컬 PC) | 로컬 PC 에서 그 포트가 점유됨. 다른 포트로 `-L` 다시 |
| 콜백이 안 옴 | SSH `-L` 이 안 걸림. 로컬에서 `ss -tlnp \| grep <port>` 로 LISTEN 확인 |
| `Invalid redirect_uri` | `claude` 가 기대하는 포트와 SSH `-L` 포트가 다름. 양쪽 일치시키기 |
| `clock skew` / `token signature invalid` | NTP 동기화 안 됨. `timedatectl set-ntp true` |
| 토큰 자주 만료 | 디스크 가득 → 토큰 갱신 쓰기 실패. `df -h ~` 확인 |
| 재인증 후에도 401 | 옛 자격증명이 남음. `~/.claude/credentials*` 모두 백업 후 재시도 |
| `No credentials found for profile "anthropic:claude-cli"` (OpenClaw 메시지) | 실제로는 OAuth access token 만료. `openclaw doctor` 로 확인 후 `claude /login`. [troubleshooting A6](./troubleshooting.md#a6-no-credentials-found-for-profile-anthropicclaude-cli-실제로는-만료) |
| `openclaw models auth login` 했는데 OAuth URL 이 안 뜸 | 그 명령은 OpenClaw 프로필만 갱신. 토큰은 `claude /login` 별도 필요. [troubleshooting A7](./troubleshooting.md#a7-openclaw-models-auth-login-을-해도-oauth-가-일어나지-않음) |
| `out of extra usage` (Max 구독 인데도) | claude.ai/settings/usage 의 "추가 사용량" 토글 OFF. [troubleshooting A5](./troubleshooting.md#a5-out-of-extra-usage--openclaw-가-anthropic-응답-거부-claude-max-인데도) |

---

## 7. 보안

- `~/.claude/credentials.json` 은 **OAuth 리프레시 토큰** 을 담는다. 절대 git 커밋 금지.
- 본 저장소 `.gitignore` 가 해당 파일을 제외한다.
- 백업 시에는 [`age`](https://github.com/FiloSottile/age) 등으로 암호화하여 외부 저장소로:

  ```bash
  age -p ~/.claude/credentials.json -o ~/credentials.json.age
  ```

- SSH 키 로테이션 시 `~/.claude` 백업도 함께 검토.

---

## 다음

- [03 — OpenClaw 설치](./03-openclaw-install.md)
- [05 — 헤드리스 운영](./05-headless-ops.md)

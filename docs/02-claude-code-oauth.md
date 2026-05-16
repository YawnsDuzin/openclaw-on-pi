# 02 — Claude Code OAuth (헤드리스 인증, *선택*)

> 브라우저가 없는 Pi 에서 **Claude Code CLI** (사람이 직접 vibe-coding 할 때 쓰는 별도 도구) 의 OAuth 인증을 받는 방법.

> 📌 **OpenClaw 의 모델 호출과는 무관**: OpenClaw 는 BYOK 라 자체 API key 를 직접 받아 호출합니다 (Claude OAuth 토큰을 쓰지 않음). 본 절차는 사람이 SSH 로 Pi 에 들어가서 `claude -p "..."` 로 직접 작업할 때만 필요합니다. OpenClaw 만 쓸 거면 이 챕터는 스킵 가능.

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

### 2-3. claude login

```bash
claude login
```

다음 형태로 URL 이 출력된다:

```
Open this URL in your browser:
  https://console.anthropic.com/oauth/authorize?...&redirect_uri=http%3A%2F%2Flocalhost%3A54545%2Fcallback&...
```

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

- OAuth 액세스 토큰은 단명(short-lived) 이지만 리프레시 토큰으로 자동 갱신된다.
- 리프레시 토큰 자체가 회수되거나 장기 미사용 시 재인증 필요.
- 헬스체크가 토큰 파일 mtime 으로 나이를 추적한다 ([`scripts/healthcheck.sh`](../scripts/healthcheck.sh), 기본 60일 경과 시 경고).
- 재인증 절차는 위 2절과 동일. 기존 자격증명을 백업한 뒤 다시 진행:

```bash
mv ~/.claude/credentials.json ~/.claude/credentials.json.bak.$(date +%s)
bash scripts/oauth-tunnel.sh
claude login
```

---

## 5. 트러블슈팅

| 증상 | 원인 / 해결 |
|---|---|
| `Address already in use` (로컬 PC) | 로컬 PC 에서 그 포트가 점유됨. 다른 포트로 `-L` 다시 |
| 콜백이 안 옴 | SSH `-L` 이 안 걸림. 로컬에서 `ss -tlnp \| grep <port>` 로 LISTEN 확인 |
| `Invalid redirect_uri` | `claude` 가 기대하는 포트와 SSH `-L` 포트가 다름. 양쪽 일치시키기 |
| `clock skew` / `token signature invalid` | NTP 동기화 안 됨. `timedatectl set-ntp true` |
| 토큰 자주 만료 | 디스크 가득 → 토큰 갱신 쓰기 실패. `df -h ~` 확인 |
| 재인증 후에도 401 | 옛 자격증명이 남음. `~/.claude/credentials*` 모두 백업 후 재시도 |

---

## 6. 보안

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

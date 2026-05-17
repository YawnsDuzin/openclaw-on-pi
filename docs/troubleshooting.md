# Troubleshooting — 자주 깨지는 지점들

> 증상 → 진단 → 해결 순으로 정리. 새 케이스는 PR 환영.
>
> Quickstart 진행 중 막혔다면 [`00-quickstart.md` 의 "막혔을 때" 표](./00-quickstart.md#막혔을-때) 가 증상 카테고리 → 본 문서 절(A–G) 매핑을 보여줍니다.

각 항목은 다음 형식:

> **증상** — 한 줄 설명
> **확인** — 1초 안에 진단 가능한 명령
> **해결** — 가장 흔한 원인부터

---

## A. OAuth / 인증

### A1. `claude login` 후에도 콜백이 안 옴

**확인**: 로컬 PC 에서 `ss -tlnp | grep 54545` (Linux/macOS) 또는 `netstat -an | findstr 54545` (Windows)

**해결**:

1. SSH 세션을 `-L 54545:localhost:54545` 로 다시 열었는지 — 기존 세션엔 적용 안 됨
2. Pi 측에서 `claude login` 이 실제로 그 포트를 사용하는지 stdout 확인 (다른 포트일 수 있음)
3. 방화벽이 LOOPBACK 까지 막진 않는지: `sudo ufw status verbose`

### A2. `Invalid redirect_uri`

**확인**: `claude login` 출력의 `redirect_uri=http%3A%2F%2Flocalhost%3A<port>` 가 SSH `-L` 의 LPORT 와 같은지

**해결**: 같은 포트로 양쪽 일치. 다르면 SSH 세션을 같은 LPORT 로 다시.

### A3. 401 / `token signature invalid`

**확인**: `timedatectl` (NTP 동기화 상태)

**해결**:

```bash
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd
```

시계가 5분 이상 차이나면 OAuth 토큰 검증이 실패. NTP 가 죽어있는 게 가장 흔한 원인.

### A4. 토큰 자동 갱신 실패

**확인**: `df -h ~` (디스크 가득), `ls -la ~/.claude/` (권한 변경 여부)

**해결**:

- 디스크 여유 확보
- 권한 복구: `chmod 700 ~/.claude && chmod 600 ~/.claude/credentials.json`
- 그래도 실패면 재인증: `mv ~/.claude/credentials.json{,.bak.$(date +%s)} && claude login`

### A5. `out of extra usage` — OpenClaw 가 Anthropic 응답 거부 (Claude Max 인데도)

**증상**: TUI 또는 채널 봇에서 메시지가 다음 메시지로 실패

```
LLM error invalid_request_error: You're out of extra usage.
Add more at claude.ai/settings/usage and keep going.
```

claude.ai/settings/usage 들어가 보면 플랜 한도(주간/세션)는 한 자릿수%만 사용한 상태.

**원인**: OpenClaw 는 `claude -p` (Claude Code CLI 의 programmatic / headless 모드) 로 호출한다. 이 경로는 사람 대화형 사용과 **다른 청구 풀** — "추가 사용량"(extra usage) 풀 — 을 통해 빌링된다. Anthropic 이 자동화 트래픽에 명시적 동의 게이트를 두기 위한 구조.

claude.ai/settings/usage 의 **추가 사용량 토글이 OFF** 면 잔액이 있어도 사용 불가 → 위 에러.

**확인**:

1. claude.ai/settings/usage 페이지 우측 "추가 사용량" 스위치 색상 — 회색=OFF, 컬러=ON
2. Pi 측에서 `openclaw doctor` 의 "Model auth" 절이 `valid` 로 나오는지 (이건 OAuth 자체는 살아 있다는 뜻 → A6 와 구분)

**해결** (셋 중 택일):

- **권장**: claude.ai/settings/usage 의 **추가 사용량 토글 ON** + 월 지출 한도 안전선 설정. (Pi 무인 운영 시 자동 충전 잔액 권장 $5–20)
- API key 방식 전환 — 구독과 완전 분리, 종량 과금. `openclaw configure` → "Anthropic API key" 선택
- 다음 5h 윈도우 리셋 대기 (임시방편 — 같은 빈도로 또 부딪힘)

> 💡 이 함정은 첫 운영자 100% 가 부딪힌다. "OpenClaw 는 Claude OAuth 구독을 못 쓴다" 는 잘못된 루머의 1차 출처 — 실제로는 **토글 한 번이면 풀린다**.

### A6. `No credentials found for profile "anthropic:claude-cli"` (실제로는 만료)

**증상**: TUI 또는 채널 봇이 다음 에러로 실패

```
⚠️ Agent failed before reply: No credentials found for profile "anthropic:claude-cli".
```

`~/.claude/.credentials.json` 은 존재하고 권한도 정상. OpenClaw 의 메시지가 오해를 유발 — 실제로는 OAuth **access token 이 만료**된 상태.

**확인**:

```bash
openclaw doctor 2>&1 | grep -A3 'Model auth'
```

다음 중 하나:

- `valid` → 다른 원인 (A5 의 빌링, 모델 ID 오타 등)
- `expiring (Nh)` → 아직 유효, N 시간 후 만료 예정
- `expired (0m)` → **이 케이스. 재인증 필요**

**원인**: Claude CLI OAuth 의 access token TTL ≈ 8 시간. OpenClaw 공식 docs 는 "expired 시 자동 refresh" 라고 명시하나, **실제로는 refresh 가 실패하고 위 에러를 반환**하는 케이스가 자주 관찰됨 (docs/구현 불일치).

**해결**:

```bash
# Pi 에서 (인터랙티브)
claude                   # Claude TUI 열기
# TUI 안에서:
/login                   # OAuth 플로우, 브라우저 URL 출력
# 인증 완료 후:
/exit                    # 또는 Ctrl+C 두 번
```

```bash
# 검증
openclaw doctor 2>&1 | grep -A3 'Model auth'   # expiring (8h) 로 바뀜
```

**무인 운영이라면 (강력 권장)** — A8 의 `claude setup-token` 으로 장기 토큰 사용:

```bash
claude setup-token       # 일회성, 만료 사실상 없음. 8h refresh 사이클 우회.
```

### A7. `openclaw models auth login` 을 해도 OAuth 가 일어나지 않음

**증상**: `openclaw models auth login --provider anthropic` → "Claude CLI" 선택 → 출력에 "Auth profile 갱신" 메시지만 뜨고 **OAuth URL 도 코드 입력도 없음**. 끝났다고 생각하지만 [A6](#a6-no-credentials-found-for-profile-anthropicclaude-cli-실제로는-만료) 에러는 그대로.

**원인**: 이 명령은 **OpenClaw 의 auth 프로필 설정만 갱신**한다. 실제 OAuth 토큰은 Claude Code CLI 가 별도 관리 (`~/.claude/.credentials.json`) — OpenClaw 가 그걸 위임해서 읽을 뿐. 따라서 진짜 재인증은 Claude CLI 쪽 명령이 필요.

**확인**: 위 명령 출력에 다음 같은 OAuth URL이 **없으면** 실제 토큰 갱신이 안 된 것:

```
Open this URL in your browser:
  https://console.anthropic.com/oauth/authorize?...
```

**해결**: [A6](#a6-no-credentials-found-for-profile-anthropicclaude-cli-실제로는-만료) 의 `claude` → `/login` 절차를 별도로 진행.

### A8. 무인 운영 — 8 시간마다 재인증을 피하려면

**상황**: Pi 가 24/7 운영. 8 시간마다 사람이 `claude /login` 하는 건 비현실적.

**해결**: Claude Code CLI 의 장기 토큰 모드:

```bash
claude setup-token       # 일회성 인터랙티브, Claude 구독 필요
```

> "Set up a long-lived authentication token (requires Claude subscription)" — `claude --help` 발췌

이 토큰은 access/refresh 토큰 사이클을 우회하므로 8h TTL 문제 없음. `~/.claude/` 하위에 저장되며 OpenClaw 는 그대로 위임 사용. 분실/회수 시까지 유효.

**대안**: API key (`ANTHROPIC_API_KEY`) — 구독과 완전 분리, 종량 과금. `openclaw configure` 재실행하여 인증 모드 변경.

---

## B. systemd / 운영

### B1. 유닛이 곧장 재시작 루프

**확인**: `journalctl -u openclaw.service -n 50 --no-pager`

**해결**: 거의 항상 `EnvironmentFile`, `ExecStart` 경로, 또는 사용자 권한 문제. 다음 순서로:

1. `systemd-analyze verify /etc/systemd/system/openclaw.service` (시스템 모드) 또는 `systemd-analyze --user verify ~/.config/systemd/user/openclaw.service` (user 모드)
2. `sudo -u openclaw bash -lc 'openclaw gateway --help'` — 사용자 자격으로 직접 실행
3. `EnvironmentFile=-/etc/openclaw/openclaw.env` 의 `-` (선두 dash) 가 빠지면 파일 부재 시 실패
4. `ExecStart` 의 PATH 에 `openclaw` 바이너리 위치가 포함되어 있는지 — system 모드는 `/opt/openclaw/.npm-global/bin/openclaw`, user 모드는 `$HOME/.npm-global/bin/openclaw`

### B2. `Failed to start due to access denied`

**확인**: 유닛의 `User=`, `WorkingDirectory=`, `ReadWritePaths=` 와 실제 디렉토리 권한

**해결**:

```bash
sudo chown -R openclaw:openclaw /opt/openclaw /var/lib/openclaw /var/log/openclaw
```

### B3. 워치독이 끊임없이 FAIL

**확인**: `journalctl -u openclaw-watchdog.service --since "30 min ago"` 의 마지막 FAIL 메시지

**해결**: healthcheck.sh 가 무엇을 FAIL 했는지 메시지가 정확히 알려준다 (token / disk / mem / network / unit). 해당 항목 진단으로 이동.

### B4. 초기 설치 직후 `Gateway: not detected (timeout)` (false negative)

**증상**: `openclaw onboard` 마법사 끝부분 또는 `openclaw status` 에서:

```
Health check failed: connect ECONNREFUSED 127.0.0.1:18789
Gateway: not detected (timeout)
```

수 초 뒤 재확인하면 정상.

**원인**: systemd 가 서비스를 `Started` 로 표시하는 시점과 Node 프로세스가 18789 포트 LISTEN 을 잡는 시점 사이에 race. 마법사가 retry 없이 한 번만 호출해서 false negative.

**확인**: 30초 정도 기다린 후

```bash
systemctl --user is-active openclaw-gateway     # active
ss -tlnp 2>/dev/null | grep 18789               # LISTEN 라인 나옴
```

**해결**: 거의 항상 그냥 무시 + 재확인. 1분이 지나도 살아나지 않으면 [B1](#b1-유닛이-곧장-재시작-루프) 절차로 진행.

### B5. 비대화형 SSH / cron / systemd 단위 에서 `openclaw: command not found`

**증상**: 대화형 shell 에선 `openclaw` 가 잘 찾히는데, ssh 단발 명령 / cron / 사용자 hook 에서는 못 찾음.

**원인**: `~/.npm-global/bin` 이 비대화형 shell 의 PATH 에 없음. `~/.bashrc` 의 PATH 추가는 보통 `[ -z "$PS1" ] && return` 보다 뒤에 와서 비대화형에선 적용 안 됨.

**확인**:

```bash
ssh dzp@pi 'which openclaw; echo $PATH'    # which 가 비어 있으면 PATH 미적용
```

**해결** (택일):

1. **절대경로 사용** (systemd 단위 / 짧은 명령에 권장):

   ```ini
   ExecStart=/home/dzp/.npm-global/bin/openclaw gateway --port 18789
   ```

2. **PATH 영구 등록** — `~/.profile` 에 추가 (대화/비대화 모두 적용, [C6](#c6-install-claude-codesh-직후-claude-명령어를-찾을-수-없음) 동일 패턴):

   ```bash
   grep -qxF 'export PATH="$HOME/.npm-global/bin:$PATH"' ~/.profile \
     || echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.profile
   ```

3. **systemd user `environment.d`** — 사용자 세션 전역에 PATH:

   ```bash
   mkdir -p ~/.config/environment.d
   cat > ~/.config/environment.d/npm-global.conf <<'EOF'
   PATH=$HOME/.npm-global/bin:$PATH
   EOF
   ```

---

## C. 빌드 / 의존성

### C1. `npm install -g` 가 EACCES

**확인**: `npm config get prefix`

**해결**: 글로벌 prefix 를 사용자 홈으로:

```bash
mkdir -p ~/.npm-global
npm config set prefix ~/.npm-global
echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

본 저장소의 [`scripts/install-claude-code.sh`](../scripts/install-claude-code.sh) 가 이 작업을 자동화.

### C2. ARM64 빌드 휠이 없어 컴파일이 무한정 걸림

**확인**: 설치 로그에 `Building wheel for ...` 가 5분 넘게 멈춤

**해결**:

- 빌드 도구 설치 확인: `sudo apt-get install -y build-essential python3-dev libffi-dev libssl-dev cmake`
- 메모리 부족이면 swap 확보 후 재시도 ([06-performance-tuning](./06-performance-tuning.md) §4)
- 그래도 안 되면 해당 패키지의 ARM64 prebuilt 가 있는 버전으로 다운그레이드

### C3. Node 버전 호환성

**확인**: `node --version`

**해결**: 본 가이드는 **OpenClaw 가 최소 Node 22.16 (권장 24) 요구** 라 22 또는 24 로 통일. NodeSource 로 명시적 설치:

```bash
# 22 (본 저장소 bootstrap-pi.sh 기본값)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs

# 또는 24 (권장)
curl -fsSL https://deb.nodesource.com/setup_24.x | sudo -E bash -
sudo apt-get install -y nodejs
```

Claude CLI (OpenClaw 위임 모드의 인프라) 도 Node 22+ 에서 정상 동작.

### C4. `bootstrap-pi.sh` 첫 단계에서 `dpkg가 중단되었습니다`

**증상**:

```
E: dpkg가 중단되었습니다. 수동으로 'sudo dpkg --configure -a' 명령을 실행해 문제점을 바로잡으십시오.
```

**원인**: 이전 apt/dpkg 작업이 비정상 종료. 두 가지 신호가 있다:

1. **half-configured 패키지**: `sudo dpkg --audit` 가 항목을 출력
2. **중단된 트랜잭션 저널**: `/var/lib/dpkg/updates/` 에 파일이 남음 (audit 는 비어도 apt 는 거부)

bootstrap-pi.sh 의 사전 점검이 `dpkg --audit` 만 통과시키고 (1) 만 잡던 시기에는 (2) 케이스가 빠져나갔다. 현재 스크립트는 `apt-get check` 까지 같이 보므로 양쪽 감지.

**확인**: 두 가지 모두 확인

```bash
sudo dpkg --audit                          # 비어 있어야 정상
sudo ls -A /var/lib/dpkg/updates/          # 비어 있어야 정상
sudo apt-get check                         # 정상이면 종료 코드 0, 출력 없음
```

**해결**:

```bash
# 1) dpkg 상태 복구
sudo dpkg --configure -a

# 2) 깨진 의존성 정리
sudo apt-get install -f -y
sudo apt-get clean

# 3) 부트스트랩 재실행 (idempotent — 안전)
cd ~/dzp_main/program/openclaw-on-pi
bash scripts/bootstrap-pi.sh
```

> 💡 bootstrap-pi.sh 는 위 상태를 자동 감지하여 `dpkg --configure -a` 를 시도한다. 그래도 실패하면 본 절차로 진행.

### C5. apt 락 점유 (`Could not get lock /var/lib/dpkg/lock-frontend`)

**증상**: 부트스트랩이 다음 메시지에서 멈춤

```
E: Could not get lock /var/lib/dpkg/lock-frontend - open (11: Resource temporarily unavailable)
```

**확인**: 점유 프로세스 식별

```bash
sudo fuser -v /var/lib/dpkg/lock-frontend
# 또는
sudo lsof /var/lib/dpkg/lock-frontend
ps aux | grep -E 'apt|dpkg|unattended' | grep -v grep
```

**해결**: 흔한 원인은 `unattended-upgrades` 자동 업데이트. 다음 중 하나:

- **대기**: 자동 업데이트가 끝날 때까지 (보통 1–5분)
- **종료**: `sudo systemctl stop unattended-upgrades` 후 재실행 (재부팅 시 다시 켜짐)
- **재부팅 직후 시도**: `sudo reboot` 후 1분 대기 후 재실행

⚠️ 다른 apt/dpkg 가 실행 중인데 `rm /var/lib/dpkg/lock*` 으로 락을 강제 삭제하면 패키지 DB 가 망가진다 — 절대 금지.

### C6. `install-claude-code.sh` 직후 `claude: 명령어를 찾을 수 없음`

**증상**: 설치는 성공("설치 완료: 2.1.x")이지만 다음 줄에서:

```
$ claude --version
-bash: claude: 명령어를 찾을 수 없음
$ bash scripts/oauth-tunnel.sh
[err] claude 바이너리가 없습니다. install-claude-code.sh 먼저.
```

**원인**: 스크립트는 npm 글로벌 prefix 를 `~/.npm-global` 로 설정해 sudo 없이 설치한다. 설치 자체는 성공하지만 **부모 셸의 PATH 는 변경되지 않으므로** 다음 명령에서 `claude` 를 찾지 못한다.

**확인**:

```bash
ls -la ~/.npm-global/bin/claude       # 존재해야 정상
echo "$PATH" | tr ':' '\n' | grep npm  # ~/.npm-global/bin 가 보이면 정상
```

**해결**:

```bash
# 1) 현재 셸에 1회 적용
export PATH="$HOME/.npm-global/bin:$PATH"
claude --version                      # 확인

# 2) 영구 등록 (idempotent — 두 번 실행해도 중복 추가 안 됨)
grep -qxF 'export PATH="$HOME/.npm-global/bin:$PATH"' ~/.bashrc \
  || echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

> 💡 현재 `install-claude-code.sh` 는 `~/.bashrc`/`~/.zshrc` 에 자동 등록한다. 이미 등록된 환경이면 새 SSH 세션부터 자동 적용 — 현재 세션만 위 옵션 1로 즉시 적용하면 됨.

---

## D. 메모리 / 성능

### D1. OOM 으로 워커가 죽음

**확인**: `dmesg | grep -i 'killed process'` 또는 `journalctl -k --since "1 hour ago" | grep -i oom`

**해결**:

- 동시 실행 줄이기: `~/.openclaw/openclaw.json` 의 `agents.list[*].concurrency: 1` (또는 단일 에이전트면 `agents.defaults.concurrency: 1`)
- zram 활성화 ([06-performance-tuning](./06-performance-tuning.md) §4-1)
- 모델 다운그레이드 (Sonnet → Haiku) — 작업 성격에 따라

### D2. 응답이 점점 느려짐

**확인**: `vcgencmd get_throttled` (Pi)

**해결**: 0x0 이 아니면 throttling. 쿨링 / 전원 / 케이스 통기 점검. 아니라면 `htop` 으로 어떤 프로세스가 CPU 를 잡는지 확인.

### D3. 디스크 가득

**확인**: `df -h /`

**해결**:

```bash
# npm 캐시
npm cache clean --force

# pip 캐시
rm -rf ~/.cache/pip

# journald 회전
sudo journalctl --vacuum-time=14d

# OpenClaw 로그
sudo find /var/log/openclaw -name "*.log.*.gz" -mtime +14 -delete
```

---

## E. 에이전트 호출 / 도구 사용

### E1. OpenClaw 응답이 안 옴 / 무한 대기

**확인**:

```bash
# gateway 살아있는가
(echo >/dev/tcp/127.0.0.1/18789) 2>&1 && echo "gateway up"

# user 모드 daemon
systemctl --user status openclaw

# 최근 로그
journalctl --user -u openclaw -n 50 --no-pager
```

**해결**:

- timeout 명시: `~/.openclaw/openclaw.json` 의 `agents.defaults.timeoutSeconds` 또는 스킬 SKILL.md 의 frontmatter `metadata.openclaw.timeoutSeconds`
- provider 응답 지연 확인: BYOK API key 모드면 `agents.defaults.model.primary` 의 키가 만료/한도 초과 아닌지. 위임 모드면 [A5](#a5-out-of-extra-usage--openclaw-가-anthropic-응답-거부-claude-max-인데도) / [A6](#a6-no-credentials-found-for-profile-anthropicclaude-cli-실제로는-만료)
- systemd 유닛의 `TimeoutStopSec` 도 비현실적으로 길지 않은지

### E2. OpenClaw 스킬이 도구 호출에 막힘

**확인**: 응답 로그에 `tool denied` / `bin not in requires` / `policy violation`

**해결**:

- SKILL.md frontmatter 의 `metadata.openclaw.requires.bins` 에 필요한 바이너리 명시 (`gh`, `jq` 등)
- `~/.openclaw/openclaw.json` 의 `tools.*.policy` / `browser.ssrfPolicy.hostnameAllowlist` 확인 — deny 우선이라 명시적 allow 가 필요
- 절대 `Bash(*)` 같은 와일드카드 화이트리스트 금지 — [docs/07 §4](./07-openclaw-hardening.md#4-스킬-clawhub-안전-정책)

### E3. 같은 스킬이 무한 재시도 / 동일 이슈 반복 처리

**확인**:

```bash
journalctl --user -u openclaw | grep -E 'skill=cleanup-issue' | wc -l
ls /tmp/pr-bot-state/recent-issues.txt   # 캐시 파일 존재 여부
```

**해결**:

- examples/github-pr-bot 처럼 외부 상태 캐시 + 락 TTL 패턴을 스킬 본문 절차로 강제
- OpenClaw 의 cron job 정의에 `maxRetries: 1` + `onFailure: stop` (스키마는 버전마다 다를 수 있으니 [공식 docs](https://docs.openclaw.ai/) 확인)
- 의심 시 일단 cron 비활성 후 수동 1회 트리거로 디버깅

### E4. 스킬이 매칭되지 않음 (모델이 다른 스킬을 호출하거나 무시)

**확인**: `openclaw skills list` 에 본 스킬이 보이는지. SKILL.md frontmatter 의 `description` 이 명확한지.

**해결**:

- `description` 은 **언제 사용하는지** 까지 구체적으로 — 모델이 이름이 아니라 상황 묘사로 매칭
- `user-invocable: true` 와 함께 슬래시 명령으로 강제 호출 (`/skill-name`)
- 다른 비슷한 스킬이 우선 매칭된다면 그쪽 description 도 조정

---

## F. 네트워크

### F1. `Could not resolve host`

**확인**: `getent hosts api.anthropic.com`

**해결**: DNS 가 죽음. `/etc/resolv.conf` 확인, `systemctl restart systemd-resolved`. 라우터 DHCP 가 이상 DNS 를 푸시하면 정적 DNS (1.1.1.1, 8.8.8.8) 로 강제.

### F2. 간헐적 SSL 핸드셰이크 실패

**확인**: `curl -v https://api.anthropic.com 2>&1 | grep -i ssl`

**해결**:

- `ca-certificates` 갱신: `sudo apt-get install --reinstall ca-certificates`
- 시스템 시계 (A3 와 동일)
- 약한 Wi-Fi → 유선 권장

---

## G. 보안 경고

### G1. fail2ban 이 자기 IP 를 밴

**확인**: `sudo fail2ban-client status sshd`

**해결**: `/etc/fail2ban/jail.local` 의 `ignoreip` 에 자기 IP/대역 추가:

```ini
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 192.168.0.0/16
```

### G2. credentials.json 이 git status 에 보임

**확인**: `git check-ignore -v ~/.claude/credentials.json`

**해결**: 본 저장소의 `.gitignore` 가 해당 파일을 제외한다. 실수로 add 했다면:

```bash
git rm --cached <path>/credentials.json
git commit -m "chore: drop accidentally tracked credentials"
# 추가로 Anthropic 콘솔에서 토큰 즉시 회수 + 재인증
```

---

## H. 채널 (Telegram / 페어링 / TUI)

### H1. 페어링 큐가 gateway 재시작 시 휘발

**증상**: 사용자가 봇에 DM 보냄 → 봇이 페어링 코드 응답 (예: `JS62TGEC`) → 운영자가 `openclaw pairing approve telegram JS62TGEC` 실행 → `No pending pairing request found for code "..."` 에러.

**원인**: 페어링 큐는 메모리(또는 휘발성 store) 보관. **gateway 재시작이 큐를 비움**. 사용자가 코드 받은 후 운영자 승인 직전에 `systemctl --user restart openclaw-gateway` 같은 게 끼면 큐가 청소됨.

**확인**:

```bash
openclaw pairing list telegram     # "No pending..." 이면 큐 비었음
```

**해결**: 사용자에게 **다시 DM** 요청 (예: "hi" 한 번 더). 새 페어링 코드가 발급되면 그걸로 승인. 운영자가 setup 직후 gateway 만지고 있는 상황이면, **gateway 만지는 작업 모두 끝낸 후** 사용자에게 페어링 시도 요청.

> 💡 이상적으로는 큐가 디스크에 영속화돼야 함 — 추후 OpenClaw 개선 후보.

### H2. TUI 에 재로그인 전 stale 실패 메시지가 새 세션에 다시 표시

**증상**: `claude /login` 으로 재인증 후 `openclaw tui` 재실행하면, 새 세션인데도 이전 만료 시점의 다음 메시지들이 화면 상단에 표시됨:

```
⚠️ Agent failed before reply: No credentials found for profile "anthropic:claude-cli".
```

새 메시지 보내면 정상 응답이 와서 그 위 stale 에러는 무시해도 됨.

**원인**: TUI 가 세션 로그를 그대로 표시 — 이전 attempt 의 실패 기록이 세션에 남아 있음. 재인증 후 다시 호출하면 성공이지만, 과거 실패 기록은 사라지지 않음.

**확인**: stale 에러 뒤에 새 입력에 대한 실제 응답(agent 메시지) 이 오면 정상.

**해결**:

- 신경 쓰이면 새 세션 생성: 슬래시 명령 `/new` 또는 세션 ID 다른 걸로 시작
- 또는 무시 — 다음 응답이 정상이면 문제 없음

### H3. Telegram 그룹 메시지가 silently drop

**증상**: 봇이 추가된 그룹에서 명령을 보내도 응답 없음. DM 은 정상.

**확인**:

```bash
openclaw config get channels.telegram.groupPolicy     # "allowlist" 같은 값
openclaw config get channels.telegram.groupAllowFrom  # 빈 배열이면 모든 그룹 drop
openclaw security audit | grep -A2 'allowFrom'        # CRITICAL 로 잡힘
```

**해결** (의도에 따라):

```bash
# 그룹 안 쓸 거면 — 가장 안전
openclaw config set channels.telegram.groupPolicy "off"

# 특정 사용자에게 그룹 명령 허용
openclaw config set channels.telegram.groupAllowFrom '["telegram:<user_id>"]' --strict-json

# 적용
systemctl --user restart openclaw-gateway
```

### H4. 페어링 후에도 owner-only 명령 거부

**증상**: 페어링은 통과해서 채팅은 되는데, `/diagnostics` `/config` 같은 권한 명령은 거부.

**원인**: DM 페어링 승인 ≠ command owner. doctor 가 명시:

> "DM pairing only lets someone talk to the bot; it does not make that sender the owner for privileged commands."

**해결**: `commands.ownerAllowFrom` 에 본인 ID 명시 (페어링 시 봇 응답에 본인 텔레그램 ID 가 포함됨):

```bash
openclaw config set commands.ownerAllowFrom '["telegram:8095251995"]' --strict-json
systemctl --user restart openclaw-gateway
```

> ⚠ 위 JSON 배열 값은 `--strict-json` 플래그 없이는 string 으로 해석되어 validation 실패함.

---

## 추가 보고

위 리스트에 없는 케이스는 [bug 이슈 템플릿](../.github/ISSUE_TEMPLATE/bug.yml) 으로 신고하면 본 문서에 반영한다.

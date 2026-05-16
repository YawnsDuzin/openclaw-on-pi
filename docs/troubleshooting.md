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

Claude Code CLI 도 Node 22+ 에서 정상 동작.

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

> 본 가이드는 두 종류의 호출 경로가 공존: (1) **OpenClaw 의 자율 에이전트** (`openclaw agent --skill X` / 메시징 채널), (2) **Claude Code CLI** (`claude -p ...`, 사람이 직접 vibe-coding). 증상이 비슷해도 점검 위치가 다르다.

### E1-OC. OpenClaw 응답이 안 옴 / 무한 대기

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
- BYOK provider 응답 지연 확인: `agents.defaults.model.primary` 의 API key 가 만료/한도 초과 아닌지
- systemd 유닛의 `TimeoutStopSec` 도 비현실적으로 길지 않은지

### E1-CC. `claude -p` (Claude Code CLI) 가 무한 대기

**확인**: 같은 명령을 `--max-turns 1` 로 다시 실행

**해결**: Claude Code 의 `~/.claude/settings.json` 에 timeout 추가. OAuth 토큰이 만료된 경우 [A4](#a4-토큰-자동-갱신-실패) 절차로 재인증. OpenClaw 와는 별 경로이므로 OpenClaw 가 살아있어도 별도로 점검.

### E2-OC. OpenClaw 스킬이 도구 호출에 막힘

**확인**: 응답 로그에 `tool denied` / `bin not in requires` / `policy violation`

**해결**:

- SKILL.md frontmatter 의 `metadata.openclaw.requires.bins` 에 필요한 바이너리 명시 (`gh`, `jq` 등)
- `~/.openclaw/openclaw.json` 의 `tools.*.policy` / `browser.ssrfPolicy.hostnameAllowlist` 확인 — deny 우선이라 명시적 allow 가 필요
- 절대 `Bash(*)` 같은 와일드카드 화이트리스트 금지 — [docs/07 §4](./07-openclaw-hardening.md#4-스킬-clawhub-안전-정책)

### E2-CC. Claude Code 의 도구 사용 거부 (`permission denied`)

**확인**: Claude Code 출력에 `denied by settings`

**해결**: `~/.claude/settings.json` 의 `permissions.allow` 에 해당 도구 패턴 추가. 추가 전에 정말 안전한 명령인지 검증 — `Bash(*)` 같은 와일드카드는 절대 금지.

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

## 추가 보고

위 리스트에 없는 케이스는 [bug 이슈 템플릿](../.github/ISSUE_TEMPLATE/bug.yml) 으로 신고하면 본 문서에 반영한다.

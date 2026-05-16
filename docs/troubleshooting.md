# Troubleshooting — 자주 깨지는 지점들

> 증상 → 진단 → 해결 순으로 정리. 새 케이스는 PR 환영.

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

1. `systemd-analyze verify /etc/systemd/system/openclaw.service`
2. `sudo -u openclaw bash -lc '/usr/bin/openclaw run --help'` — 사용자 자격으로 직접 실행
3. `EnvironmentFile=-/etc/openclaw/openclaw.env` 의 `-` (선두 dash) 가 빠지면 파일 부재 시 실패

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

**해결**: Claude Code 는 Node 20 LTS 권장. NodeSource 로 명시적 설치:

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
```

---

## D. 메모리 / 성능

### D1. OOM 으로 워커가 죽음

**확인**: `dmesg | grep -i 'killed process'` 또는 `journalctl -k --since "1 hour ago" | grep -i oom`

**해결**:

- 동시 실행 줄이기: `openclaw.yaml` 의 `queues[].max_concurrent: 1`
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

## E. 작업 큐 / Claude Code 호출

### E1. `claude -p` 가 무한 대기

**확인**: 같은 명령을 `--max-turns 1` 로 다시 실행

**해결**: 설정에 timeout 을 명시 (`openclaw.yaml` 의 `runtime.claude_code.timeout_seconds`). systemd 유닛의 `TimeoutStopSec` 도 비현실적으로 길지 않은지 확인.

### E2. 도구 사용이 거부됨 (`permission denied`)

**확인**: Claude Code 의 출력에 `denied by settings`

**해결**: `settings.json` 의 `permissions.allow` 에 해당 도구 패턴 추가. 추가 전에 정말 안전한 명령인지 검증할 것 — `Bash(*)` 같은 와일드카드는 절대 금지.

### E3. 같은 작업이 무한 재시도

**확인**: `journalctl -u openclaw.service | grep -E "task=<id>" | wc -l`

**해결**: OpenClaw 의 재시도 정책에 백오프와 max-retry 가 있는지. 없으면 dead-letter 큐로 이동시키도록 task 정의 갱신.

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

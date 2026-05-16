# 05 — Headless Ops: tmux · systemd · 원격 운용

> 모니터/키보드 없이 Pi 를 24/7 가동하기 위한 tmux 세션 · systemd 유닛 · 로그 수집 · 원격 접근.

⚠ 검증 환경: systemd 252+ (Bookworm). Ubuntu Server 24.04 도 포맷 호환.

---

## 1. tmux — 첫 디버깅 단계

처음 며칠은 systemd 로 백그라운드 보내기 전에 **tmux** 로 띄워두고 SSH 끊어도 살아있게 한다.

```bash
tmux new -s openclaw
# 안에서:
openclaw run --log-level debug
# Ctrl+b d  → 분리
# 다시 보려면:  tmux attach -t openclaw
```

장점: 로그를 그대로 보면서 즉시 Ctrl+C 가능.
단점: 부팅 시 자동 시작 X, OOM 으로 죽으면 자동 재시작 X.

→ 안정화되면 systemd 로 옮긴다.

---

## 2. systemd — 운영 단계

본 저장소가 제공:

- [`configs/systemd/openclaw.service`](../configs/systemd/openclaw.service) — 본 에이전트
- [`configs/systemd/openclaw-watchdog.service`](../configs/systemd/openclaw-watchdog.service) — 워치독

### 2-1. 사전 준비

전용 사용자 + 디렉토리:

```bash
sudo useradd -r -m -d /opt/openclaw -s /usr/sbin/nologin openclaw
sudo mkdir -p /opt/openclaw/scripts /etc/openclaw /var/lib/openclaw /var/log/openclaw
sudo chown -R openclaw:openclaw /opt/openclaw /var/lib/openclaw /var/log/openclaw

# 본 저장소 클론을 /opt/openclaw 아래에 또는 심볼릭링크
sudo cp scripts/healthcheck.sh /opt/openclaw/scripts/
sudo chmod +x /opt/openclaw/scripts/healthcheck.sh

# 설정 파일
sudo cp configs/openclaw.example.yaml /etc/openclaw/openclaw.yaml
sudo chown root:openclaw /etc/openclaw/openclaw.yaml
sudo chmod 640 /etc/openclaw/openclaw.yaml
```

OAuth 토큰을 openclaw 사용자도 쓰게 하려면:

```bash
sudo mkdir -p /opt/openclaw/.claude
sudo cp ~/.claude/credentials.json /opt/openclaw/.claude/
sudo cp ~/.claude/settings.json    /opt/openclaw/.claude/   # 있으면
sudo chown -R openclaw:openclaw /opt/openclaw/.claude
sudo chmod 700 /opt/openclaw/.claude
sudo chmod 600 /opt/openclaw/.claude/credentials.json
```

> 보안상 평소 사용 유저와 openclaw 시스템 유저를 분리하라. credentials 는 복사가 아닌 별도 인증을 권장하지만, 본 가이드에서는 단순화를 위해 복사 절차를 명시.

### 2-2. 유닛 설치

```bash
sudo cp configs/systemd/openclaw.service           /etc/systemd/system/
sudo cp configs/systemd/openclaw-watchdog.service  /etc/systemd/system/

# 워치독 timer (5분마다 healthcheck)
sudo tee /etc/systemd/system/openclaw-watchdog.timer >/dev/null <<'EOF'
[Unit]
Description=Run OpenClaw watchdog periodically

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=30s
Unit=openclaw-watchdog.service

[Install]
WantedBy=timers.target
EOF

sudo systemd-analyze verify /etc/systemd/system/openclaw.service \
                            /etc/systemd/system/openclaw-watchdog.service \
                            /etc/systemd/system/openclaw-watchdog.timer

sudo systemctl daemon-reload
sudo systemctl enable --now openclaw.service openclaw-watchdog.timer
```

### 2-3. 상태 확인

```bash
systemctl status openclaw.service
systemctl list-timers openclaw-watchdog.timer
journalctl -u openclaw.service -n 100 -f
```

---

## 3. 로그

### 3-1. journald → 파일

systemd 유닛이 stdout 을 `/var/log/openclaw/openclaw.log` 에 append 하도록 설정해 두었다. journald 도 동시에 받으므로 두 군데서 조회 가능.

`logrotate` 설정 (하루 1회 회전, 14일 보관):

```bash
sudo tee /etc/logrotate.d/openclaw >/dev/null <<'EOF'
/var/log/openclaw/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    create 0640 openclaw openclaw
}
EOF
```

### 3-2. 빠른 트리아지

```bash
# 최근 에러만
journalctl -u openclaw.service -p err -n 200 --no-pager

# 워치독 결과
journalctl -u openclaw-watchdog.service --since "1 hour ago" --no-pager

# 큐 처리 추적 (OpenClaw 가 task id 를 stdout 에 찍는다고 가정)
journalctl -u openclaw.service -n 500 | grep -E "task=[0-9a-f-]+"
```

---

## 4. 원격 접근

### 4-1. SSH 하드닝

```bash
sudo sed -i \
    -e 's/^#\?PermitRootLogin .*/PermitRootLogin no/' \
    -e 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' \
    -e 's/^#\?ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' \
    /etc/ssh/sshd_config

sudo systemctl reload ssh
sudo apt-get install -y fail2ban
```

포트 22 → 임의 포트(예: 2244) 변경은 ufw 규칙도 같이 갱신:

```bash
sudo ufw allow 2244/tcp comment 'ssh-custom'
sudo ufw delete allow 22/tcp
```

### 4-2. 외부 망에서 접근

홈 라우터 포트포워딩 대신 다음 중 하나를 권장:

- [Tailscale](https://tailscale.com/) — 가장 간편. WireGuard 메시 VPN
- [Cloudflare Tunnel](https://www.cloudflare.com/products/tunnel/) — TCP 접근 가능
- 자체 [WireGuard](https://www.wireguard.com/) — 완전한 통제권

자세한 설정은 [`recipes/remote-vibe-coding`](../recipes/remote-vibe-coding.md) 참고.

---

## 5. 자동 업데이트 — 신중하게

24/7 노출 디바이스라면 보안 패치는 자동 적용이 안전하다:

```bash
sudo apt-get install -y unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

단, **OpenClaw / Node.js / Claude Code 자동 업데이트는 비추천**. 인터페이스 변경이 잦으므로 수동 + 헬스체크 후 적용.

---

## 6. 배터리 / 정전 대비

- 유닛 `Restart=on-failure` 가 프로세스 죽음에는 대응하지만, 정전엔 무력
- 짧은 정전 보호: 미니 UPS HAT (PiSugar 등) 또는 데스크톱 UPS
- 부팅 후 NTP 동기화 전 OAuth 호출이 실패할 수 있으니 유닛에 `After=time-sync.target` 추가 가능

---

## 다음

- [06 — Performance Tuning](./06-performance-tuning.md)
- [troubleshooting](./troubleshooting.md)
- [recipes/scheduled-agent-tasks](../recipes/scheduled-agent-tasks.md)

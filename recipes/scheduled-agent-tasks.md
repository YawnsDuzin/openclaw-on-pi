# Recipe — cron 기반 스케줄 작업

> OpenClaw 자체 스케줄러 대신 OS 의 cron 또는 systemd timer 를 사용해 작업을 정기 enqueue 한다.

⚠ 검증 환경: cron (Vixie cron, Bookworm 기본) 및 systemd timer 양쪽.

---

## 시나리오

- OpenClaw 본체는 큐 워커로만 두고, 스케줄링은 OS 가 책임
- "주간 리뷰 노트 자동 작성", "매일 03:00 backup-status 점검" 같은 단순 정기 작업
- 작업 정의를 한 군데(crontab) 에서 보고 싶을 때

---

## 필요 조건

- [03 — OpenClaw 설치](../docs/03-openclaw-install.md) 완료
- OpenClaw 가 systemd 로 가동 중 ([05 — Headless Ops](../docs/05-headless-ops.md))

---

## 단계

### 방법 A — user crontab

```bash
crontab -e
```

```cron
# m h dom mon dow
0 3 * * *  /usr/bin/openclaw enqueue --queue default --task daily-backup-check >> ~/cron.log 2>&1
0 9 * * 1  /usr/bin/openclaw enqueue --queue low --task weekly-review >> ~/cron.log 2>&1
30 2 * * * /opt/openclaw/scripts/healthcheck.sh >> ~/cron.log 2>&1
```

장점: 가장 단순.
단점: 환경변수 / PATH 가 인터랙티브 셸과 달라 종종 실패. crontab 첫 줄에 `PATH=...` 명시.

### 방법 B — systemd timer (권장)

각 작업을 `.service` + `.timer` 페어로:

```bash
sudo tee /etc/systemd/system/openclaw-daily-backup-check.service >/dev/null <<'EOF'
[Unit]
Description=OpenClaw — daily backup check

[Service]
Type=oneshot
User=openclaw
ExecStart=/usr/bin/openclaw enqueue --queue default --task daily-backup-check
EOF

sudo tee /etc/systemd/system/openclaw-daily-backup-check.timer >/dev/null <<'EOF'
[Unit]
Description=Run daily backup check at 03:00

[Timer]
OnCalendar=*-*-* 03:00:00
RandomizedDelaySec=120
Persistent=true
Unit=openclaw-daily-backup-check.service

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now openclaw-daily-backup-check.timer
```

확인:

```bash
systemctl list-timers | grep openclaw
journalctl -u openclaw-daily-backup-check.service --since "yesterday"
```

장점: 실패/성공 추적이 journald 로 깔끔. `Persistent=true` 로 Pi 가 꺼졌다 켜져도 놓친 실행 보강.
단점: 작업이 늘면 유닛 파일 관리 부담 → Ansible / Nix 같은 정의 도구 도움.

---

## 운영 팁

- **랜덤 지연**: 모든 작업이 정각에 몰리면 OAuth/네트워크가 동시 부하. `RandomizedDelaySec` 또는 cron 의 분 jitter 활용
- **실행 로그**: 표준 출력은 항상 어딘가에 저장. cron 은 `>> ~/cron.log 2>&1`, systemd 는 journald 자동
- **실패 알림**: systemd 의 `OnFailure=` 를 사용해 ntfy / 이메일 트리거 유닛 호출
- **드라이 런**: 첫 등록 시 `--dry-run` (OpenClaw 가 지원한다면) 으로 enqueue 만 시뮬레이션

---

## 알려진 한계

- **동시 실행 충돌**: 두 timer 가 같은 시각에 큰 작업을 트리거하면 워커가 막힘. 큐의 `max_concurrent` + timer 시각 분산
- **cron 환경**: `claude` / `openclaw` 의 PATH, `HOME` 누락이 가장 흔한 실패. 첫 줄 `SHELL=/bin/bash`, `PATH=...`, `HOME=/home/<user>` 명시
- **DST / 타임존**: `OnCalendar` 는 시스템 타임존 기준. UTC 가 명확하면 `OnCalendar=UTC ...` 로 고정

---

## 다음

- [자율 코딩 루프](./auto-coding-loop.md)
- [troubleshooting](../docs/troubleshooting.md)

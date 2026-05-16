# Recipe — 스케줄 작업 (cron 패턴)

> 스킬을 정기 트리거하는 두 가지 방법: OpenClaw 내장 `cron.jobs` (권장) vs OS cron / systemd timer (외부).

⚠ 검증 환경: OpenClaw ≥ 2026.2.6, 시스템 cron (Vixie, Bookworm 기본), systemd timer.

> 📜 2026-05-16 재작성 라운드 — 1차 라운드의 `openclaw enqueue --task` 명령은 가상이었음. 실제는 (a) OpenClaw 의 cron 내장 또는 (b) systemd timer 가 `openclaw agent --skill` 을 호출.

---

## 시나리오

- "주간 리뷰 노트 자동 작성" (월요일 9시)
- "매일 03:00 backup-status 점검"
- "매시 5분 로그 트리아지" → [`examples/log-triage`](../examples/log-triage/) 가 표준 예제

---

## 옵션 A — OpenClaw 내장 cron (권장)

`~/.openclaw/openclaw.json` 의 `cron.jobs` 배열에 등록. 가장 깔끔하고 OpenClaw 가 직접 관리 (재시작/실패 추적/락 모두 자동).

```json5
{
  cron: {
    enabled: true,
    jobs: [
      // 매시 5분 — 로그 트리아지
      { schedule: "5 * * * *",  skill: "log-triage" },

      // 매일 03:00 — 백업 상태 점검
      { schedule: "0 3 * * *",  skill: "backup-status" },

      // 매주 월요일 09:00 — 주간 리뷰
      { schedule: "0 9 * * 1",  skill: "weekly-review" },

      // 6시간마다 — PR 자동 정리
      { schedule: "0 */6 * * *", skill: "cleanup-issue",
        env: { PR_BOT_REPO: "youruser/yourrepo" } },
    ],
  },
}
```

문법 검증 + 재기동:

```bash
openclaw config validate
systemctl --user restart openclaw
openclaw cron list                # 등록된 job 확인
journalctl --user -u openclaw -n 50 | grep cron
```

장점: OpenClaw 가 락 / 재시도 / 실패 알림 모두 일관 처리. 한 곳에 정의.
단점: OS cron 으로 익숙한 운영자에겐 새 학습 비용.

---

## 옵션 B — systemd timer (외부, OpenClaw 가 jobs 키를 미지원할 때)

각 작업을 `.service` + `.timer` 페어로:

```bash
sudo tee /etc/systemd/system/openclaw-log-triage.service >/dev/null <<'EOF'
[Unit]
Description=OpenClaw — log-triage skill (hourly)

[Service]
Type=oneshot
User=dzp
Environment=PATH=/home/dzp/.npm-global/bin:/usr/local/bin:/usr/bin:/bin
EnvironmentFile=-/home/dzp/.openclaw-secrets/log-triage.env
ExecStart=/home/dzp/.npm-global/bin/openclaw agent --skill log-triage
EOF

sudo tee /etc/systemd/system/openclaw-log-triage.timer >/dev/null <<'EOF'
[Unit]
Description=Run log-triage every hour

[Timer]
OnCalendar=*-*-* *:05:00
RandomizedDelaySec=120
Persistent=true
Unit=openclaw-log-triage.service

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now openclaw-log-triage.timer
```

확인:

```bash
systemctl list-timers | grep openclaw
journalctl -u openclaw-log-triage.service --since "yesterday"
```

장점: 실패/성공 추적이 journald 로 깔끔. `Persistent=true` 로 Pi 가 꺼졌다 켜져도 놓친 실행 보강.
단점: 작업이 늘면 유닛 파일 관리 부담. Ansible / Nix 도움.

---

## 옵션 C — user crontab (가장 단순)

`crontab -e`:

```cron
SHELL=/bin/bash
PATH=/home/dzp/.npm-global/bin:/usr/local/bin:/usr/bin:/bin
HOME=/home/dzp

# m h dom mon dow
5 * * * *  openclaw agent --skill log-triage         >> ~/cron-openclaw.log 2>&1
0 3 * * *  openclaw agent --skill backup-status      >> ~/cron-openclaw.log 2>&1
30 2 * * * /home/dzp/dzp_main/program/openclaw-on-pi/scripts/healthcheck.sh >> ~/cron-openclaw.log 2>&1
```

장점: 가장 단순.
단점: 환경변수 / PATH 누락이 흔한 실패 → crontab 첫 줄에 `PATH=...` 명시.

---

## 운영 팁

- **랜덤 지연**: 모든 작업이 정각에 몰리면 BYOK provider 한도가 동시 부하. `RandomizedDelaySec` (systemd) 또는 cron 의 분 jitter 활용
- **실행 로그**: cron 은 `>> ~/cron.log 2>&1`, systemd 는 journald 자동
- **실패 알림**: systemd 의 `OnFailure=` 를 사용해 ntfy / 이메일 트리거 유닛 호출
- **드라이 런**: 첫 등록 시 SKILL.md 의 절대 규칙에 `--dry-run` 옵션 + 본인 채널 알림으로 결과만 확인

---

## 알려진 한계

- **동시 실행 충돌**: 두 trigger 가 같은 시각에 큰 작업이면 워커가 막힘. 옵션 A 의 OpenClaw 내장 락 + 시각 분산 권장
- **cron 환경**: `openclaw` 의 PATH, `HOME` 누락이 가장 흔한 실패. 옵션 C 의 첫 3줄 `SHELL/PATH/HOME` 누락 금지
- **DST / 타임존**: `OnCalendar` 는 시스템 타임존 기준. UTC 가 명확하면 `OnCalendar=UTC ...` 로 고정

---

## 다음

- [자율 코딩 루프](./auto-coding-loop.md)
- [troubleshooting](../docs/troubleshooting.md)

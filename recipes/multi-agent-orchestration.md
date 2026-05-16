# Recipe — 멀티 에이전트 오케스트레이션

> Pi 한 대에서 여러 OpenClaw 인스턴스를 역할별로 분리해 큐 / 권한 / 토큰 / 자원 사용을 분리.

⚠ 검증 환경: Pi 5 (8GB) 권장. Pi 4 4GB 에서는 N=2 가 현실적 상한.

---

## 시나리오

- "트리아지 봇" + "코딩 봇" + "리포팅 봇" 처럼 책임을 분리해 안전 모델을 다르게 운영
- 각 봇이 다른 권한 화이트리스트 / 다른 OAuth 구독(가족 계정 vs 본인) / 다른 큐 우선순위
- 하나가 폭주해도 다른 봇이 살아있게

---

## 필요 조건

- Pi 5 (8GB) + NVMe 권장 ([06 — Performance Tuning](../docs/06-performance-tuning.md))
- 각 인스턴스용 별도 시스템 사용자 (격리)
- 각 인스턴스용 별도 Claude OAuth 자격증명

---

## 단계

### 1) 사용자 + 디렉토리 분리

```bash
for role in triage coder reporter; do
    sudo useradd -r -m -d /opt/openclaw-${role} -s /usr/sbin/nologin openclaw-${role}
    sudo mkdir -p /etc/openclaw-${role} /var/lib/openclaw-${role} /var/log/openclaw-${role}
    sudo chown -R openclaw-${role}:openclaw-${role} \
         /opt/openclaw-${role} /var/lib/openclaw-${role} /var/log/openclaw-${role}
done
```

### 2) 역할별 설정

`/etc/openclaw-coder/openclaw.yaml` (예):

```yaml
agent:
  name: pi-coder
  workdir: /var/lib/openclaw-coder/work

runtime:
  claude_code:
    binary: claude
    settings: /opt/openclaw-coder/.claude/settings.json
    model: claude-sonnet-4-6

queues:
  - name: default
    max_concurrent: 1
```

`/etc/openclaw-triage/openclaw.yaml` 은 `model: claude-haiku-4-5-20251001`, `max_concurrent: 2` 등 가볍게.
`/etc/openclaw-reporter/openclaw.yaml` 은 read-only 권한만.

### 3) 권한 분리 (settings.json)

| 역할 | 추가 deny |
|---|---|
| triage | `Edit(*)`, `Write(*)` (읽기만) |
| coder | `Bash(gh repo delete:*)`, `Bash(git push --force:*)` |
| reporter | `Bash(*)` 거의 전체 (특정 read-only 만 allow) |

### 4) systemd 유닛 템플릿화

`/etc/systemd/system/openclaw@.service`:

```ini
[Unit]
Description=OpenClaw instance %i
After=network-online.target

[Service]
Type=simple
User=openclaw-%i
Group=openclaw-%i
WorkingDirectory=/opt/openclaw-%i
ExecStart=/usr/bin/openclaw run --config /etc/openclaw-%i/openclaw.yaml
Restart=on-failure
RestartSec=10s

# 메모리 / 태스크 제한 (Pi 5 8GB 기준 보수적)
MemoryHigh=1.5G
MemoryMax=2G
TasksMax=256

NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/var/lib/openclaw-%i /var/log/openclaw-%i

[Install]
WantedBy=multi-user.target
```

활성화:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now openclaw@triage openclaw@coder openclaw@reporter
```

### 5) 큐 간 통신

세 봇이 협력하려면 **공유 큐 백엔드** (Redis / Postgres / SQLite + 락) 가 필요. OpenClaw 가 외부 큐 백엔드를 지원하는지 확인 후 구성.

간단한 패턴:

- triage 가 `coder-queue` 에 enqueue
- coder 가 작업 완료 후 `reporter-queue` 에 enqueue
- reporter 가 결과를 issue 코멘트로 게시

---

## 운영 팁

- **리소스 모니터**: `systemd-cgtop` 로 인스턴스별 CPU/메모리 확인
- **로그 통합**: `journalctl -u 'openclaw@*' -f` 로 전체 한눈에
- **모델 핀 테스트**: triage 만 Haiku 로 돌려도 정확도가 충분한 경우가 많음 → 비용 절감
- **점진 도입**: 처음엔 인스턴스 1개로 시작, 안정화되면 분리

---

## 알려진 한계

- **OAuth 토큰 공유 불가**: 같은 Anthropic 계정의 토큰을 N개 인스턴스에서 동시 사용 시 정책 위반 가능 — 계정/플랜 정책 사전 확인
- **레이트 리밋 합산**: 여러 봇이 같은 구독을 쓰면 한도 합산. 큐 처리량을 미리 계산
- **메모리 압박**: Pi 4 4GB 는 2개도 빠듯. zram / swap 필수
- **장애 전파**: 공유 큐가 장애나면 모두 멈춤 → 큐 백엔드의 HA 또는 정기 백업

---

## 다음

- [자율 코딩 루프](./auto-coding-loop.md)
- [06 — Performance Tuning](../docs/06-performance-tuning.md)

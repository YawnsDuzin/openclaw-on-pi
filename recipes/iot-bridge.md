# Recipe — IoT 브릿지 (GPIO / MQTT)

> Pi 의 GPIO / I²C / MQTT 센서 데이터를 OpenClaw 스킬이 받아 LLM 으로 해석·요약·알림한다.

⚠ 검증 환경: Pi 5 + DHT22 (온습도) / BME280 (기압) / 자체 MQTT 브로커. 실제 센서 / 액추에이터 조합은 다양하므로 본 레시피는 패턴 위주.

> 📜 2026-05-16 재작성 라운드 — 1차 라운드의 `tasks.yaml` 가상 스키마 폐기, SKILL.md + cron.jobs 패턴.

---

## 시나리오

- 거실 온습도 + 미세먼지 센서가 1분 단위로 SQLite 에 기록 중
- 매 시간 `/env-summary` 스킬이 최근 1시간 데이터를 요약 + 이상치를 자연어로 알림 (Telegram / ntfy)
- "지난 3시간 추이가 평소와 다르면" 같은 자연어 규칙을 LLM 이 판정

LLM 의 강점은 **수치를 자연어로 요약하고 사람의 일정과 결합해 행동 제안**. 단순 임계 알림은 별도 룰엔진 (Node-RED) 이 효율적.

---

## 필요 조건

- Pi 의 GPIO/I²C/SPI 활성 (`sudo raspi-config` → Interface Options)
- 센서 라이브러리 (예: `pip install adafruit-circuitpython-dht`)
- MQTT 브로커 (선택) — `mosquitto`
- OpenClaw + cron.jobs 동작 ([03 — OpenClaw](../docs/03-openclaw-install.md))

---

## 단계

### 1) 센서 → 시계열 저장 (별 프로세스)

데이터 수집은 LLM 이 아닌 별도 스크립트가 담당.

`/opt/sensors/collect.py`:

```python
#!/usr/bin/env python3
import sqlite3, time, board, adafruit_dht
from datetime import datetime

dht = adafruit_dht.DHT22(board.D4)
db = sqlite3.connect('/var/lib/sensors/sensors.db')
db.execute("""
  CREATE TABLE IF NOT EXISTS readings (
    ts TEXT, sensor TEXT, key TEXT, value REAL
  )
""")

def emit(key, value):
    db.execute("INSERT INTO readings VALUES (?,?,?,?)",
               (datetime.utcnow().isoformat(), 'dht22', key, value))
    db.commit()

while True:
    try:
        emit('temperature_c', dht.temperature)
        emit('humidity_pct',  dht.humidity)
    except RuntimeError:
        pass  # DHT22 는 가끔 read 실패 정상
    time.sleep(60)
```

systemd 유닛 + restart 정책으로 24/7 가동.

### 2) `env-summary` 스킬 정의

`~/.openclaw/skills/env-summary/SKILL.md`:

```markdown
---
name: env-summary
description: 거실 환경 (온습도/기압/미세먼지) 의 최근 1시간 데이터를 요약하고 이상치를 한 줄로 보고한다. /var/lib/sensors/sensors.db 의 readings 테이블만 읽고 결과를 ntfy 로 발행한다.
user-invocable: true
metadata:
  openclaw:
    requires:
      bins: [sqlite3, jq, curl]
---

# env-summary

## 절차

1. sqlite3 로 readings 테이블에서 지난 60분 데이터 SELECT
2. 평균/최대/최소 (온도, 습도), 직전 1시간 대비 변화율 계산
3. 평균±3σ 밖 이상치 발견 시 시각/값 별도 보고
4. JSON `{ title, body }` 형태로 `/opt/sensors/notify.sh` 호출

## 절대 규칙

- /var/lib/sensors/sensors.db 외 다른 파일 R/W 금지
- 외부 네트워크는 ntfy.sh 하나만 (notify.sh 가 처리)
- 액추에이터 (릴레이/모터) 직접 제어 절대 금지 — 룰엔진 통해서만

## 출력

`/opt/sensors/notify.sh` 호출 결과만. stdout 에 별도 출력 없음.
```

### 3) cron 등록 — 매시 5분

`~/.openclaw/openclaw.json`:

```json5
{
  cron: {
    enabled: true,
    jobs: [
      { schedule: "5 * * * *", skill: "env-summary" },
    ],
  },
}
```

### 4) 알림 어댑터

`/opt/sensors/notify.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
JSON="${1:?usage: notify.sh <json>}"
TOPIC="${NTFY_TOPIC:?env NTFY_TOPIC required}"
TITLE="$(jq -r '.title // "환경 요약"' <<< "$JSON")"
BODY="$(jq -r '.body  // .'           <<< "$JSON")"
curl -fsS -H "Title: $TITLE" -d "$BODY" "https://ntfy.sh/$TOPIC"
```

`NTFY_TOPIC` 은 systemd EnvironmentFile (`~/.openclaw-secrets/iot.env`) 로 주입.

---

## 운영 팁

- **데이터 양 컨트롤**: 1시간치 raw 데이터는 60행. 1주일치를 매번 LLM 에 넣으면 토큰 폭발 → 사전 집계 (분→시간→일) 후 전달
- **이상 감지는 통계로**: 단순 z-score / IQR 은 LLM 없이 처리 가능. LLM 은 "이상이 발견됐을 때 사람 친화적 문장 작성" 에만 사용
- **GPIO 권한**: 수집 사용자를 `gpio` 그룹에 추가 (`sudo usermod -aG gpio <user>`). OpenClaw 가 돌리는 사용자는 DB read-only 권한만 — 권한 격리
- **하드웨어 안전**: 액추에이터 제어는 LLM 직접 호출 절대 금지. 룰엔진 (Node-RED / Home Assistant) 을 사이에 두고 화이트리스트된 동작만

---

## 알려진 한계

- **실시간성 X**: LLM 호출 자체가 수초 ~ 수십초. 즉시 반응이 필요한 제어에 부적합
- **DHT22 read 실패**: 30초당 1회 정도는 RuntimeError 정상. 수집 루프는 try/except 흡수
- **DB lock**: SQLite 동시 쓰기 충돌. 대용량이면 InfluxDB / TimescaleDB 권장
- **민감 데이터**: 카메라 / 마이크 데이터는 절대 LLM 으로 보내지 말 것 — 별도 동의 / 익명화 필요
- **Prompt Injection (센서 데이터)**: 이론적으로 센서가 받은 텍스트 (예: NFC 태그 본문) 에 숨긴 지시문이 있을 수 있음. 가능하면 LLM 에 넣기 전 화이트리스트 / 필드 분리

---

## 다음

- [자율 코딩 루프](./auto-coding-loop.md)
- [멀티 에이전트 오케스트레이션](./multi-agent-orchestration.md)
- [07 — Hardening](../docs/07-openclaw-hardening.md)

# Example — log-triage

> systemd journald + 애플리케이션 로그를 LLM 으로 요약·분류·우선순위화하는 봇 예제.

⚠ **상태: 코드 작성 완료, 실 로그 검증 X**
정적 리뷰만 통과한 best-effort 구현. 실 운영 전 반드시 `LOG_TRIAGE_PUBLISH=stdout` 으로 1주일 그림자 가동 + 마스킹 sed 룰셋 검증.

---

## 의도

- 매시간 (또는 사용자 cron) 실행
- 입력: `journalctl --since "1 hour ago" -p warning..err` + 추가 로그 파일 (선택)
- 가공: 마스킹(이메일/IP/토큰/JWT/PII) → LLM 분류 → JSON 결과
- 출력: severity 별 채널 라우팅 (error → 즉시, warning → 다이제스트, info-only → 생략)

---

## 디렉토리 구조

```
log-triage/
├── README.md
├── tasks.yaml             ← OpenClaw task: pre/prompt/post/verify
├── CLAUDE.md              ← 봇 행동 규칙
├── prompts/
│   └── triage.md          ← 분류 기준 + 출력 스키마 + few-shot 2개 + 자기점검
└── scripts/
    ├── collect-logs.sh    ← journalctl + 추가 파일 수집 + 마스킹
    └── publish.sh         ← stdout/ntfy/slack/issue 채널 라우팅 + 패턴 캐시 갱신
```

---

## 환경변수

### 수집 (collect-logs.sh)

| 변수 | 의미 | 기본 |
|---|---|---|
| `LOG_TRIAGE_SINCE` | 조회 범위 | `1 hour ago` |
| `LOG_TRIAGE_PRIORITY` | journalctl `-p` | `warning` |
| `LOG_TRIAGE_UNITS` | 콤마 구분 유닛 필터 | (전체) |
| `LOG_TRIAGE_EXTRA` | 추가 cat 할 로그 파일 (콤마) | (없음) |

### 발행 (publish.sh)

| 변수 | 의미 | 기본 |
|---|---|---|
| `LOG_TRIAGE_PUBLISH` | `stdout` \| `ntfy` \| `slack` \| `issue` | `stdout` |
| `LOG_TRIAGE_STATE_DIR` | 상태/캐시 디렉토리 | `/var/lib/log-triage` |
| `LOG_TRIAGE_SUPPRESS_INFO` | `1` 이면 info-only 결과 발행 생략 | `1` |
| `NTFY_TOPIC` | publish=ntfy 일 때 필수 | — |
| `NTFY_SERVER` | ntfy 서버 | `https://ntfy.sh` |
| `SLACK_WEBHOOK_URL` | publish=slack 일 때 필수 | — |
| `GITHUB_REPO` | publish=issue 일 때 필수 (`user/repo`) | — |

---

## 수동 실행

```bash
# 1) 수집만 — 출력 형식 / 마스킹 동작 확인
bash examples/log-triage/scripts/collect-logs.sh | head -50

# 2) 끝-끝 (stdout)
mkdir -p /tmp/log-triage-work
bash examples/log-triage/scripts/collect-logs.sh > /tmp/log-triage-work/input.txt

claude -p \
  --add-dir examples/log-triage \
  --output-format json \
  "$(cat examples/log-triage/prompts/triage.md)" \
  > /tmp/log-triage-work/output.json

LOG_TRIAGE_PUBLISH=stdout bash examples/log-triage/scripts/publish.sh \
  /tmp/log-triage-work/output.json
```

OpenClaw 로 자동화하려면 `tasks.yaml` 의 schedule (`5 * * * *`) 그대로 사용하거나 [`recipes/scheduled-agent-tasks`](../../recipes/scheduled-agent-tasks.md) 의 systemd timer 패턴 적용.

---

## 출력 JSON 스키마

`prompts/triage.md` 가 강제하는 형식:

```json
{
  "summary": "한 줄 요약",
  "window": "ISO-8601 / ISO-8601",
  "issues": [
    {
      "severity": "error" | "warning" | "info",
      "count": 정수,
      "pattern": "정규화된 메시지",
      "first_seen": "ISO-8601",
      "sample": "마스킹된 원본 1줄",
      "suggested_action": "한 단계로 따라할 수 있는 명령/체크",
      "is_new": true | false,
      "unit": "systemd unit 또는 null"
    }
  ]
}
```

스키마 위반 시 `tasks.yaml` 의 `post` 단계가 `jq -e` 로 거부 → OpenClaw 재시도.

---

## 마스킹 룰

`scripts/collect-logs.sh` 의 `mask()` 함수 — sed 기반:

| 패턴 | 대체 |
|---|---|
| 이메일 | `<email>` |
| IPv4 | `<ip>` |
| `Bearer ...` / `Authorization: Bearer ...` | `Bearer <token>` |
| 한국 휴대전화 (`010-1234-5678`) | `<phone>` |
| 신용카드 추정 16자리 | `<card>` |
| `/home/<user>/...` | `/home/USER/...` |
| `sk-...` (Anthropic/OpenAI key 형식) | `<api-key>` |
| `ghp_...` (GitHub PAT) | `<gh-token>` |
| `eyJ...` (JWT) | `<jwt>` |

⚠ **이 룰셋은 출발점이며 완전하지 않다.** IPv6, MAC 주소, 사내 호스트네임, 회원번호 등 도메인별 PII 패턴을 추가하라. 가능하면 [`detect-secrets`](https://github.com/Yelp/detect-secrets) 를 추가 패스로 통합.

---

## 새 패턴 (`is_new`) 판정

- `seen-patterns.json` 에 직전 패턴 SHA-256 해시 최대 1000개 보관
- LLM 이 `pattern` 을 정규화하여 출력 → publish.sh 가 해시 계산 후 union 갱신
- 첫 등장 패턴은 `is_new=true` → ntfy 의 `Priority: urgent` / Slack 의 강조

---

## 안전장치

| 위험 | 대응 |
|---|---|
| 민감정보가 LLM 으로 전송 | `mask()` 함수 + LLM 출력에도 토큰 형태 보존 강제 |
| LLM 출력 스키마 위반 | `tasks.yaml` post 단계 `jq -e` 거부 → 재시도 |
| 같은 알림 폭주 | `is_new` 캐시 + `LOG_TRIAGE_SUPPRESS_INFO=1` |
| 채널 인증정보 노출 | env 파일은 600 권한 + git 제외 |
| 큰 입력 토큰 폭발 | CLAUDE.md 의 "5000줄 넘으면 패턴 그룹별 1개 sample" 규칙 |

---

## 검증 후 할 일

`LOG_TRIAGE_PUBLISH=stdout` 로 1주일 가동 + 마스킹 누락 케이스 보강 → 실 채널 활성화. 이후:

- 본 README 의 ⚠ → ✅
- 루트 README 의 examples 표 마커 갱신
- 누락 패턴 / 오분류 케이스를 `prompts/triage.md` few-shot 에 추가

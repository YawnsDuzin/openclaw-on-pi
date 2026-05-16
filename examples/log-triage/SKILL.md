---
name: log-triage
description: systemd journald + 애플리케이션 로그를 LLM 으로 분류/요약/우선순위화한다. 매시간 cron 으로 자동 실행하거나, 사용자가 '/log-triage' 슬래시 명령으로 즉시 트리거할 수 있다. 마스킹된 입력만 다루며, severity 별로 다른 채널 (ntfy/Slack/Issue/stdout) 로 결과를 발행한다.
user-invocable: true
metadata:
  openclaw:
    requires:
      env:
        - LOG_TRIAGE_PUBLISH
      bins:
        - journalctl
        - jq
        - sha256sum
        - sed
---

# log-triage (skill)

> ⚠ **상태: 코드 작성 완료, 실 로그 검증 X**
> 첫 운영 시 반드시 `LOG_TRIAGE_PUBLISH=stdout` 으로 1주일 그림자 가동 + 마스킹 룰셋 검증.

## 의도

매시간 (또는 슬래시 명령) journald + 추가 로그 파일을 수집 → 마스킹 → JSON 분류 → severity 별 채널 라우팅 (`error` 즉시 / `warning` 다이제스트 / `info` 생략). 출력은 엄격한 JSON 스키마를 따른다 — 위반 시 OpenClaw 가 거부.

## 트리거

- **Cron**: `~/.openclaw/openclaw.json` 의 `cron.jobs` 에 `"5 * * * *"` (매시 5분) 등록 시 자동 실행
- **슬래시 명령**: 페어링된 채널에서 `/log-triage` → 즉시 실행
- **수동**: `openclaw agent --skill log-triage` (테스트용)

## 환경변수

| 변수 | 의미 | 기본 |
|---|---|---|
| `LOG_TRIAGE_SINCE` | journalctl 조회 범위 | `1 hour ago` |
| `LOG_TRIAGE_PRIORITY` | journalctl `-p` 우선순위 | `warning` |
| `LOG_TRIAGE_UNITS` | 콤마 구분 유닛 필터 (선택) | (전체) |
| `LOG_TRIAGE_EXTRA` | 추가 cat 할 로그 파일 (콤마) | (없음) |
| `LOG_TRIAGE_STATE_DIR` | 상태/캐시 디렉토리 | `/var/lib/log-triage` |
| `LOG_TRIAGE_PUBLISH` | `stdout` \| `ntfy` \| `slack` \| `issue` | `stdout` |
| `LOG_TRIAGE_SUPPRESS_INFO` | `1` 이면 info-only 결과 발행 생략 | `1` |
| `NTFY_TOPIC` / `NTFY_SERVER` | publish=ntfy 일 때 | — / `https://ntfy.sh` |
| `SLACK_WEBHOOK_URL` | publish=slack 일 때 | — |
| `GITHUB_REPO` | publish=issue 일 때 (`user/repo`) | — |

env 보관: `~/.openclaw-secrets/log-triage.env` (권한 600) → systemd `EnvironmentFile=-...` 로 주입.

## 실행 절차

1. **로그 수집 + 마스킹** — `bash scripts/collect-logs.sh > /tmp/log-triage-work/input.txt`. 출력 라인 형식: `<ISO-8601 ts> <unit?> <severity> <message>`. 마스킹 룰은 [§마스킹](#마스킹-룰) 참고.

2. **상태 파일 준비** — `${LOG_TRIAGE_STATE_DIR}/seen-patterns.json` (없으면 `{"patterns":[]}` 로 간주).

3. **LLM 분류** — 본 SKILL.md 본문 + `references/triage-rules.md` (정규화 규칙 + few-shot + 자기점검) 를 시스템 프롬프트로. 모델은 `input.txt` 와 `seen-patterns.json` 을 읽어 `/tmp/log-triage-work/output.json` 에 [§출력 스키마](#출력-스키마) 형태로 저장.

4. **스키마 검증**:

   ```bash
   OUT="/tmp/log-triage-work/output.json"
   [[ -s "$OUT" ]] || exit 1
   jq -e '.summary and .issues' "$OUT" >/dev/null || exit 1
   ```

   위반 시 OpenClaw 가 1회 재시도.

5. **발행** — `bash scripts/publish.sh /tmp/log-triage-work/output.json`. 채널 (`stdout` / `ntfy` / `slack` / `issue`) 에 따라 라우팅 + `seen-patterns.json` 갱신.

## 출력 스키마

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

**스키마 위반은 곧장 재시도 대상.** 키를 빠뜨리거나 추가하지 말 것.

자세한 분류 기준 / 정규화 규칙 / `is_new` 판정 / few-shot 2건 / 자기 점검 체크리스트는 → [`references/triage-rules.md`](references/triage-rules.md).

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

## 절대 규칙

- **마스킹된 입력만 다룰 것** — 원본 raw 로그를 다시 읽지 말 것 (도구로 journalctl 재호출 금지)
- **외부 네트워크 호출 금지** — 발행은 `publish.sh` 만 처리, 모델 본인은 외부로 나가지 말 것
- **시스템 파일 / 다른 사용자 디렉토리 접근 금지**
- 파일 쓰기는 `/tmp/log-triage-work/` 안에서만
- 마스킹된 토큰 (`<email>`, `<ip>` 등) 을 복원하려고 시도하지 말 것 — 출력에 그대로 보존

## 토큰 예산

- 입력 라인이 5000 줄 넘으면 동일 패턴 그룹별 대표 sample 1개씩만 남기고 요약
- 출력 JSON 길이 ≤ 32KB

## 안전장치

| 위험 | 대응 |
|---|---|
| 민감정보가 LLM 으로 전송 | `mask()` 함수 + 본 SKILL.md 의 마스킹 토큰 보존 강제 |
| LLM 출력 스키마 위반 | 위 §4 의 `jq -e` 거부 → OpenClaw 1회 재시도 |
| 같은 알림 폭주 | `is_new` 캐시 + `LOG_TRIAGE_SUPPRESS_INFO=1` |
| 채널 인증정보 노출 | env 파일 권한 600 + git 제외 |
| Prompt injection (로그 본문에 숨긴 지시문) | 마스킹 후에도 위험. [docs/07 §6](../../docs/07-openclaw-hardening.md#6-prompt-injection-운영-완화) 운영 완화 참고 |
| 큰 입력 토큰 폭발 | 위 토큰 예산 규칙 |

## 검증 (스킬 종료 후)

- `/tmp/log-triage-work/output.json` 존재 + `jq -e '.summary and .issues'` 통과
- `/tmp/log-triage-work/published.flag` 존재 (publish.sh 가 마지막에 touch)

둘 다 OK 면 성공.

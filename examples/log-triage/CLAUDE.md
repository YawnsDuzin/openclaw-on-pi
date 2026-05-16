# 프로젝트 컨텍스트 — log-triage

systemd journald + 애플리케이션 로그를 LLM 으로 분류·요약·우선순위화한다.

## 입력 형태

- `/tmp/log-triage-work/input.txt` — 수집·마스킹된 로그 라인 (collect-logs.sh 산출)
- `prompts/triage.md` — 분류 기준 / 출력 스키마 / few-shot 예시
- `<state>/seen-patterns.json` — 직전 24시간 동안 본 패턴 해시 (새 패턴 판정용)

## 출력 형태 — 반드시 다음 JSON 스키마

```json
{
  "summary": "한 줄 요약",
  "window": "ISO-8601 범위",
  "issues": [
    {
      "severity": "error" | "warning" | "info",
      "count": 정수,
      "pattern": "정규화된 메시지 (구체값 제거)",
      "first_seen": "ISO-8601",
      "sample": "원본 1줄 (마스킹 적용된 상태)",
      "suggested_action": "사람이 한 단계로 따라할 수 있는 명령/체크",
      "is_new": true | false,
      "unit": "systemd unit 이름 또는 null"
    }
  ]
}
```

출력은 **반드시** `/tmp/log-triage-work/output.json` 에 저장. 다른 경로/형식 금지.

## 절대 규칙

- **마스킹된 입력만 다룰 것** — 원본 raw 로그를 다시 읽지 말 것
- **외부 네트워크 호출 금지** — 발행은 publish.sh 가 별도 처리
- **시스템 파일 / 다른 사용자 디렉토리 접근 금지**
- 파일 쓰기는 `/tmp/log-triage-work/` 안에서만

## severity 판단 기준

- `error`: 서비스 영향, OOM, panic, crash, restart loop, 인증 실패 다수, 디스크/네트워크 실패
- `warning`: 한도 근접, deprecation, 단발성 retry, 비정상 종료지만 자가 회복
- `info`: 위 둘에 안 맞는 모든 것 — 가능하면 issues 에 넣지 말고 summary 에서만 언급

## 새 패턴 판정 (`is_new`)

- `seen-patterns.json` 의 키 목록에 현재 `pattern` 의 해시가 없으면 `true`
- 봇이 자체적으로 해시를 추가/갱신하지는 않음 (publish.sh 가 처리)

## 토큰 예산

- 입력 라인 수가 5000 줄 넘으면, 동일 패턴 그룹별 대표 sample 1개씩만 남기고 요약하라
- 출력 JSON 길이는 32KB 이하로

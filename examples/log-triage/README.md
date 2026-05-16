# Example — log-triage

> systemd journald / 애플리케이션 로그를 LLM 으로 요약·분류·우선순위화하는 봇 예제.

⏳ **상태: 스텁 (코드 미작성)**
실 로그 샘플로 프롬프트 튜닝이 끝난 뒤 별도 PR.

---

## 의도

- 매 1시간 또는 매일 1회 실행
- 입력: `journalctl --since "1 hour ago" -p warning..err` 출력
- 출력:
  - JSON 으로 분류된 이슈 리스트 (severity, count, first_seen, sample, suggested_action)
  - 새로 등장한 (이전 N시간 동안 보이지 않던) 패턴은 별도 강조
  - 결과를 ntfy / Slack / GitHub Issue 로 발행

LLM 의 강점: **정규식으로 잡기 어려운 새 패턴을 자연어로 잡아내고 우선순위를 사람 친화적으로 설명**.

---

## 예고된 디렉토리 구조

```
log-triage/
├── README.md
├── tasks.yaml
├── CLAUDE.md
├── prompts/
│   └── triage.md          ← 분류 기준, 출력 스키마, 예시
└── scripts/
    ├── collect-logs.sh    ← journalctl + 회전된 파일 통합 수집, 마스킹
    └── publish.sh         ← 결과 발행 (ntfy / GitHub Issue)
```

---

## 입력 가공 — 마스킹이 핵심

LLM 으로 보내기 전에 다음을 반드시 마스킹/제거:

- IP 주소 (외부) — 일관된 hash 로 치환
- 이메일 주소
- API 키 / Bearer 토큰 패턴
- 파일 경로 중 `/home/<user>/...` → `/home/USER/...`
- 호스트네임 (필요 시)

도구 예: [`detect-secrets`](https://github.com/Yelp/detect-secrets), 자체 sed 룰셋.

---

## 예고된 출력 스키마

```json
{
  "summary": "지난 1시간 warning 12건, error 3건. 새 패턴 1건.",
  "issues": [
    {
      "severity": "error",
      "count": 3,
      "pattern": "openclaw.service: Failed to start due to ...",
      "first_seen": "2026-05-16T14:03:11+09:00",
      "sample": "...",
      "suggested_action": "유닛 EnvironmentFile 경로 확인",
      "is_new": false
    }
  ]
}
```

---

## TODO (구현 시)

- [ ] 로그 마스킹 룰셋 작성 + 테스트 케이스
- [ ] `prompts/triage.md` — JSON schema + 분류 기준 예시 (few-shot)
- [ ] 새 패턴 판정 — 직전 24시간의 패턴 해시 캐시 비교
- [ ] 결과 라우팅 — severity 별 다른 채널 (error → 즉시 알림, warning → 일일 다이제스트)
- [ ] 실 로그 1주일 분량으로 프롬프트 튜닝 후 본 README 갱신

---

## 보안 주의

- **로그에는 거의 항상 민감 정보가 섞인다** — 마스킹 없이 LLM 호출 절대 금지
- LLM 출력에도 입력의 일부가 그대로 인용될 수 있음 → 발행 전 한 번 더 redaction 패스
- 로그 보존 정책 — 발행된 요약은 보관해도, 원본 raw 입력은 LLM 호출 후 즉시 폐기 권장

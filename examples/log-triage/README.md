# Example — log-triage

> systemd journald + 애플리케이션 로그를 LLM 으로 요약·분류·우선순위화하는 OpenClaw 스킬.

⚠ **상태: 코드 작성 완료, 실 로그 검증 X**
정적 리뷰만 통과한 best-effort 구현. 실 운영 전 반드시 `LOG_TRIAGE_PUBLISH=stdout` 으로 1주일 그림자 가동 + 마스킹 sed 룰셋 검증.

> 📜 2026-05-16 재작성 라운드 — 1차 라운드의 `tasks.yaml` + `prompts/triage.md` 분리 구조는 OpenClaw 의 실제 인터페이스가 아니어서 통합. 본 라운드는 SKILL.md + `references/triage-rules.md` (모델이 필요 시 참조) + bundled scripts 패턴.

---

## 의도

- 매시간 (또는 슬래시 명령) 실행
- 입력: `journalctl --since "1 hour ago" -p warning..err` + 추가 로그 파일 (선택)
- 가공: 마스킹 (이메일/IP/토큰/JWT/PII) → LLM 분류 → JSON 결과
- 출력: severity 별 채널 라우팅 (`error` 즉시 / `warning` 다이제스트 / `info` 생략)

---

## 디렉토리 구조

```
log-triage/
├── README.md                  ← 본 파일
├── SKILL.md                   ← 스킬 정의 + 절대 규칙 + 출력 스키마
├── references/
│   └── triage-rules.md        ← 정규화 규칙 + few-shot + 자기점검 (모델이 필요 시 로드)
└── scripts/
    ├── collect-logs.sh        ← journalctl + 추가 파일 수집 + 마스킹
    └── publish.sh             ← stdout/ntfy/slack/issue 채널 라우팅 + seen-patterns 갱신
```

> 💡 `references/` 는 OpenClaw 의 스킬 표준 보조 디렉토리 — SKILL.md 가 핵심 규칙을 갖고, 자주 참조 안 되는 상세 자료를 분리해 컨텍스트 비용을 절약한다.

---

## 환경변수

[SKILL.md §환경변수](SKILL.md#환경변수) 참고. 핵심:

- `PUBLISH=stdout`: 1주일 그림자 가동 (필수 시작점)
- `PUBLISH=ntfy` / `slack` / `issue`: 검증 후 활성화

env 보관: `~/.openclaw-secrets/log-triage.env` (권한 600).

---

## 설치 — 본 스킬을 OpenClaw 에 등록

```bash
DEST="$HOME/.openclaw/skills/log-triage"
mkdir -p "$DEST/scripts" "$DEST/references"
cp examples/log-triage/SKILL.md                "$DEST/SKILL.md"
cp examples/log-triage/references/*.md         "$DEST/references/"
cp examples/log-triage/scripts/*.sh            "$DEST/scripts/"
chmod +x "$DEST/scripts/"*.sh

systemctl --user restart openclaw
openclaw skills list | grep log-triage
```

---

## 수동 1회 실행 (검증용)

```bash
# 1) 수집만 — 마스킹 동작 확인
bash examples/log-triage/scripts/collect-logs.sh | head -50

# 2) 끝-끝 (stdout)
mkdir -p /tmp/log-triage-work
bash examples/log-triage/scripts/collect-logs.sh > /tmp/log-triage-work/input.txt

# 슬래시 또는 직접
openclaw agent --skill log-triage

# 출력 확인
cat /tmp/log-triage-work/output.json | jq .
```

---

## Cron 자동화

`~/.openclaw/openclaw.json` 의 `cron` 절:

```json5
{
  cron: {
    enabled: true,
    jobs: [
      { schedule: "5 * * * *", skill: "log-triage" },
    ],
  },
}
```

또는 systemd timer 로 `openclaw agent --skill log-triage` 를 호출 — [`recipes/scheduled-agent-tasks`](../../recipes/scheduled-agent-tasks.md) 패턴 참고.

---

## 출력 JSON 스키마

`SKILL.md` 가 강제하는 형식:

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

스키마 위반 시 검증 단계에서 `jq -e` 가 거부 → OpenClaw 가 1회 재시도. 자세한 분류 기준 / 정규화 규칙 / few-shot / 자기점검 → [`references/triage-rules.md`](references/triage-rules.md).

---

## 새 패턴 (`is_new`) 판정

- `seen-patterns.json` 에 직전 24시간 동안 본 패턴 SHA-256 해시 최대 1000개 보관
- LLM 이 `pattern` 을 정규화하여 출력 → `publish.sh` 가 해시 계산 후 union 갱신
- 첫 등장 패턴은 `is_new=true` → ntfy 의 `Priority: urgent` / Slack 의 강조

---

## 안전장치

[SKILL.md §안전장치](SKILL.md#안전장치) 표 참고. 핵심:

- 마스킹 출발점이며 완전하지 않음 — 도메인별 PII 추가 필수
- Prompt injection 위험 (로그 본문에 숨긴 지시문) — [docs/07 §6](../../docs/07-openclaw-hardening.md#6-prompt-injection-운영-완화)
- 첫 1주는 `stdout` 모드 + 채널 인증정보 평문 저장 위험 ([docs/07 §5](../../docs/07-openclaw-hardening.md#5-자격증명-보호--openclaw-평문-저장-대응))

---

## 검증 후 할 일

`LOG_TRIAGE_PUBLISH=stdout` 로 1주일 가동 + 마스킹 누락 케이스 보강 → 실 채널 활성화. 이후:

- 본 README 의 ⚠ → ✅
- 루트 README 의 examples 표 마커 갱신
- 누락 패턴 / 오분류 케이스를 `references/triage-rules.md` few-shot 에 추가

---

## 흔한 실패 케이스

| 증상 | 원인 / 해결 |
|---|---|
| `output.json 없음` | LLM 이 다른 경로에 저장. SKILL.md 의 "출력 위치 강제" 항목 강화 |
| `JSON 스키마 위반` | 키 누락 / 추가. `references/triage-rules.md` 의 자기점검 체크리스트 강화 |
| 마스킹 후에도 토큰 같은 문자열 노출 | `collect-logs.sh` 의 `mask()` 함수에 새 패턴 추가 |
| 모든 패턴이 `is_new=true` | `seen-patterns.json` 미생성 / `state-dir` 권한 문제. `ls -la $LOG_TRIAGE_STATE_DIR` 확인 |
| ntfy/slack 전송 실패 | env 미주입 또는 webhook URL 만료. `~/.openclaw-secrets/log-triage.env` 점검 |

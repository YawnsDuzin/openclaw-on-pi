# Example — hello-agent

> 가장 작은 OpenClaw 스킬. 메시지 → 스킬 매칭 → 모델 호출 → 응답 파이프라인 끝-끝 검증용.

⚠ **상태: 코드 작성 완료, Pi 미검증**
정적 리뷰만 통과한 best-effort 구현입니다. 실 Pi 에서 동작 검증 후 본 마커를 ✅ 로 갱신하세요.

> 📜 2026-05-16 재작성 라운드 — 1차 라운드의 `tasks.yaml + openclaw enqueue/run` 구조는 OpenClaw 의 실제 인터페이스가 아니어서 폐기. 본 라운드는 공식 [openclaw/openclaw](https://github.com/openclaw/openclaw) 의 SKILL.md + `openclaw agent --message` 호출 구조.

---

## 의도

새로 셋업한 Pi 에서:

1. [`scripts/bootstrap-pi.sh`](../../scripts/bootstrap-pi.sh) → [`install-claude-code.sh`](../../scripts/install-claude-code.sh) (Claude CLI 위임 모드 시) → [`install-openclaw.sh`](../../scripts/install-openclaw.sh) → `openclaw onboard --install-daemon` 까지 진행
2. 본 예제로 **스킬 매칭 + 모델 호출** 이 실제 일어나는지 확인

성공 시 사용자가 얻는 것:

- `~/.openclaw/skills/hello/SKILL.md` 가 설치되어 있고
- `openclaw agent --message "hello"` 가 정확히 `ok` 를 응답하고
- 종료 코드 0

---

## 디렉토리 구조

```
hello-agent/
├── README.md              ← 본 파일
├── SKILL.md               ← 스킬 정의 (frontmatter name + description + 본문)
└── run.sh                 ← 스킬 설치 + agent 호출 + 검증
```

---

## 사용법

```bash
cd /home/dzp/dzp_main/program/openclaw-work
cp -r /home/dzp/dzp_main/program/openclaw-on-pi/examples/hello-agent .
cd hello-agent

# Gateway 가 안 떠 있으면 별도 창에서 미리:
#   openclaw gateway --port 18789 --verbose

bash run.sh
```

`run.sh` 가 자동으로:

1. 본 디렉토리의 `SKILL.md` 를 `~/.openclaw/skills/hello/` 로 복사 (멱등)
2. `127.0.0.1:18789` 의 gateway 가 응답하는지 점검
3. `openclaw agent --message "hello" --thinking high` 호출
4. 응답이 정확히 `ok` (공백 제거 후) 인지 검증
5. (선택) `journalctl --user -u openclaw` 에 `skill=hello` 매칭 흔적 확인

종료 코드 0 이면 통과.

---

## 절대 규칙 (SKILL.md 와 동일)

- 파일 R/W 금지 (도구 사용 자체 금지)
- 셸 실행 금지
- 외부 네트워크 호출 금지
- 응답은 정확히 `ok` — 한 글자라도 다르면 실패

이 제약 덕분에 본 스킬은 **결정적** 으로 동작 — 동일 input 에 동일 output. 파이프라인 검증에 적합.

---

## 검증 후 할 일

Pi 에서 끝-끝 동작이 확인되면:

- 본 README 의 ⚠ → ✅
- 루트 README 의 examples 표 마커도 같이 ✅
- 실패 케이스가 있으면 [troubleshooting](../../docs/troubleshooting.md) 에 추가

---

## 흔한 실패 케이스

| 증상 | 원인 / 해결 |
|---|---|
| `openclaw 미설치` | `bash scripts/install-openclaw.sh` 먼저 |
| `Gateway 가 ... 안 떠 있습니다` | 별도 창에서 `openclaw gateway --port 18789 --verbose`, 또는 `systemctl --user start openclaw` |
| 응답이 `ok` 가 아님 | `~/.openclaw/openclaw.json` 의 `agents.defaults.model.primary` 와 해당 API key 확인. description 이 모호하면 모델이 다른 스킬을 부를 수 있음 |
| `openclaw agent` 가 401 / 인증 실패 | BYOK API key (예: Anthropic) 미설정 또는 만료. console.anthropic.com 에서 키 발급/갱신 |
| 응답이 길거나 설명이 붙음 | SKILL.md 의 "절대 규칙" 본문이 약함 — `description` 에 "정확히 'ok' 한 단어만 응답" 을 더 강하게 |

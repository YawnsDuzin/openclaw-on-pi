# Example — hello-agent

> 가장 작은 OpenClaw + Claude Code 통합 예제. 파이프라인 끝-끝 검증용.

⚠ **상태: 코드 작성 완료, Pi 미검증**
정적 리뷰만 통과한 best-effort 구현입니다. 실 Pi 에서 동작 검증 후 본 마커를 ✅ 로 갱신하세요.

---

## 의도

- 새로 셋업한 Pi 에서 [`scripts/bootstrap-pi.sh`](../../scripts/bootstrap-pi.sh) → [`install-claude-code.sh`](../../scripts/install-claude-code.sh) → [`install-openclaw.sh`](../../scripts/install-openclaw.sh) → OAuth 까지 진행한 뒤,
- 본 예제로 **Claude Code 호출이 실제로 일어나는지** 끝에서 끝까지 검증.

성공 시 사용자가 얻는 것: README.md 끝에 "OpenClaw says hi at ..." 가 추가된 새 git 커밋 1개.

---

## 디렉토리 구조

```
hello-agent/
├── README.md              ← 본 파일
├── tasks.yaml             ← OpenClaw task 정의 (verify 블록 포함)
├── CLAUDE.md              ← 프로젝트 컨텍스트 (이 디렉토리 한정)
└── run.sh                 ← 1줄 트리거 (enqueue + run --once)
```

---

## 사용법

```bash
cd /home/dzp/dzp_main/program/openclaw-work
cp -r /home/dzp/dzp_main/program/openclaw-on-pi/examples/hello-agent .
cd hello-agent

bash run.sh
```

기대:

- Claude Code 가 호출되어 README.md 끝에 한 줄 추가
- `git log --oneline` 마지막 커밋이 `chore(hello): hello-agent demo run`
- `tasks.yaml` 의 `verify:` 블록이 모두 통과 → 종료 코드 0

---

## 절대 규칙 (CLAUDE.md 와 동일)

- README.md 외 파일 수정 금지
- 새 브랜치 생성 금지
- 외부 네트워크 호출 금지
- 파괴적 git 명령 금지

---

## 검증 후 할 일

Pi 에서 끝-끝 동작이 확인되면:

- 본 README 의 ⚠ → ✅
- 루트 README 의 examples 표 마커도 같이 ✅
- 실패 케이스가 있으면 [troubleshooting](../../docs/troubleshooting.md) 에 추가

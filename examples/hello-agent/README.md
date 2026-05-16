# Example — hello-agent

> 가장 작은 OpenClaw + Claude Code 통합 예제. 파이프라인 끝-끝 검증용.

⏳ **상태: 스텁 (코드 미작성)**
실제 구현은 Pi 하드웨어 + OAuth 토큰에서 검증한 뒤 별도 PR 로 머지한다. 본 README 는 의도와 형태만 명시.

---

## 의도

- 새로 셋업한 Pi 에서 [`scripts/bootstrap-pi.sh`](../../scripts/bootstrap-pi.sh) → [`install-claude-code.sh`](../../scripts/install-claude-code.sh) → [`install-openclaw.sh`](../../scripts/install-openclaw.sh) → OAuth 까지 진행한 뒤,
- 본 예제로 **Claude Code 호출이 실제로 일어나는지** 끝에서 끝까지 검증.

성공 시 사용자가 얻는 것: README.md 끝에 "OpenClaw says hi" 가 추가된 새 git 커밋 1개.

---

## 예고된 디렉토리 구조

```
hello-agent/
├── README.md              ← 본 파일 (스텁)
├── tasks.yaml             ← OpenClaw task 정의
├── CLAUDE.md              ← 프로젝트 컨텍스트 (이 디렉토리 한정)
└── run.sh                 ← 한 줄로 enqueue + run --once 트리거
```

---

## 예고된 사용법

```bash
cd ~/openclaw-work
cp -r <repo>/examples/hello-agent .
cd hello-agent
git init -q && git add . && git commit -q -m "init"

bash run.sh
```

기대:

- Claude Code 가 호출되어 README.md 를 수정
- `git log --oneline` 마지막 커밋이 OpenClaw 가 만든 커밋
- 종료 코드 0

---

## TODO (구현 시)

- [ ] `tasks.yaml` 작성 — 단일 task `hello-write`, queue=default
- [ ] `CLAUDE.md` 최소 컨텍스트 (이 디렉토리는 hello-agent 라는 것만)
- [ ] `run.sh` 스크립트 — `openclaw enqueue` + `openclaw run --once`
- [ ] Pi 5 (8GB) 에서 끝-끝 검증 후 본 README 의 ⏳ 를 ✅ 로 갱신

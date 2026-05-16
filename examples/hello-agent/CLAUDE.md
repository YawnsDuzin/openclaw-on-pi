# 프로젝트 컨텍스트 — hello-agent

이 디렉토리는 OpenClaw + Claude Code 통합의 **최소 동작 검증** 용 데모다.

## 디렉토리 정체

- `README.md` — 작업 대상 / 결과 가시화 파일
- `tasks.yaml` — OpenClaw task 정의
- `run.sh` — 1줄 트리거 (enqueue + run --once)
- `CLAUDE.md` — 본 파일

## 절대 규칙

- **README.md 외 어떤 파일도 만지지 말 것** — 본 데모는 README 끝에 한 줄 추가만
- **새 브랜치 만들지 말 것** — 현재 브랜치 직접 커밋
- **외부 네트워크 호출 금지** — `Bash(curl:*)`, `Bash(wget:*)` 등은 settings.json 에서 deny
- **파괴적 git 명령 금지** — `git reset --hard`, `git push --force`, `git branch -D`

## 커밋 형식

```
chore(hello): <한 줄 설명>
```

## 동작 검증

`tasks.yaml` 의 `verify:` 블록이 자동 실행된다. 통과 조건:

1. 마지막 커밋 메시지가 `chore(hello): hello-agent demo run`
2. 그 커밋이 README.md 만 변경
3. README.md 에 `"OpenClaw says hi at "` 패턴 존재

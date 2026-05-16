# 04 — Integration: OpenClaw ↔ Claude Code

> 작업 큐(OpenClaw) 가 코드 작성·수정 단계를 Claude Code 에 위임하는 통합 패턴.

⚠ 검증 환경: Claude Code CLI 의 비대화형(non-interactive) 모드 (`claude -p`, `--output-format json`) 기준.

---

## 1. 책임 분리

| 도구 | 책임 |
|---|---|
| **OpenClaw** | 작업 정의 / 큐 / 우선순위 / 재시도 / 스케줄 / 워치독 |
| **Claude Code** | 1회 호출 단위의 코드 읽기·수정·테스트, OAuth 인증 보유 |
| **CLAUDE.md** | 프로젝트 컨벤션 / 금지사항 — Claude Code 가 자동 로드 |
| **settings.json** | 도구 사용 권한(허용/거부) — Claude Code 가 자동 로드 |

이 분리의 핵심: **OpenClaw 는 LLM 을 직접 호출하지 않는다.** "코드를 만져야 하는 일" 이 생기면 `claude -p` 를 셸에서 실행하는 식으로 위임한다.

---

## 2. 호출 패턴

### 2-1. 단발 (one-shot) 위임

가장 단순한 패턴. OpenClaw 의 task 가 셸 명령을 한 줄 실행:

```bash
claude -p \
  --add-dir "$WORKDIR" \
  --output-format json \
  "다음 요구사항대로 코드를 수정하고 테스트를 통과시켜라: $TASK_PROMPT"
```

핵심 옵션:

- `-p` (`--print`) : 비대화형. 응답을 stdout 으로 출력 후 종료
- `--add-dir` : Claude Code 의 작업 디렉토리. CLAUDE.md / settings.json 자동 로드
- `--output-format json` : 종료 사유 / 사용 토큰 / 도구 호출 내역 등을 구조화 → OpenClaw 가 파싱

OpenClaw 쪽은 결과 JSON 의 `stop_reason`, `usage`, `is_error` 등을 보고 성공/실패/재시도를 결정.

### 2-2. 멀티턴 (resume)

장시간 작업은 한 번의 `claude -p` 로는 컨텍스트가 넘칠 수 있다. Claude Code 는 세션 ID 로 재개 가능:

```bash
# 첫 호출
SID=$(claude -p --output-format json "step 1: ..." | jq -r .session_id)

# 같은 세션 이어서
claude -p --resume "$SID" --output-format json "step 2: ..."
```

OpenClaw 의 작업 정의에 `session_id` 필드를 두고 단계별로 enqueue.

### 2-3. 출력 캡처

stdin/stdout 으로 결과를 받는 것이 가장 단순. 커밋·테스트·빌드까지는 Claude Code 본인이 수행하게 두고, OpenClaw 는 종료코드와 git diff 로 결과를 검증.

```bash
claude -p "..." > /var/log/openclaw/last.json
echo "exit=$?"
git -C "$WORKDIR" diff --stat
```

---

## 3. CLAUDE.md 활용

`/home/dzp/dzp_main/program/openclaw-work/<project>/CLAUDE.md` 는 그 프로젝트의 영속 컨텍스트다. 다음을 적어두면 모든 호출에 자동 적용:

- 프로젝트 정체 / 디렉토리 가이드
- 코드 컨벤션 (포맷터, 들여쓰기, 커밋 형식)
- 자주 쓰는 명령 (`make test`, `npm run build`)
- "OpenClaw 자율 작업 시 추가 규칙" 섹션 — confirmation 정책, 파괴적 액션 dry-run 등

템플릿: [`configs/CLAUDE.example.md`](../configs/CLAUDE.example.md)

---

## 4. 권한 화이트리스트

Claude Code `settings.json` 의 `permissions` 가 도구 사용을 게이트한다.
24/7 자율 운영의 핵심 안전장치이므로 **deny 우선, allow 최소** 원칙으로 작성.

[`configs/claude-code-settings.example.json`](../configs/claude-code-settings.example.json) 발췌:

```jsonc
{
  "permissions": {
    "allow": [
      "Read(*)", "Glob(*)", "Grep(*)",
      "Edit(./**)", "Write(./**)",
      "Bash(git status)", "Bash(git diff:*)", "Bash(git commit:*)",
      "Bash(npm test)", "Bash(pytest:*)"
    ],
    "deny": [
      "Bash(curl:*)", "Bash(wget:*)", "Bash(ssh:*)", "Bash(scp:*)",
      "Bash(rm -rf:*)", "Bash(sudo:*)",
      "Write(/etc/**)", "Write(~/.ssh/**)", "Write(~/.claude/**)"
    ]
  }
}
```

매칭 규칙:

- 도구별로 `Tool(pattern)` 형태 — pattern 은 셸 글로브
- `Bash(git diff:*)` 처럼 `:*` 를 붙이면 인자 임의값 허용
- `deny` 가 `allow` 보다 강함

---

## 5. 작업 라이프사이클 흐름도

```
┌──────────────────────────────────────────────────────────────┐
│                       OpenClaw worker                        │
│                                                              │
│  큐에서 task pop → workdir 결정 → 환경변수 세팅              │
│        │                                                     │
│        ▼                                                     │
│  claude -p --add-dir <workdir> --output-format json "..."    │
│        │                                                     │
│        ▼                                                     │
│  result = {stop_reason, usage, is_error, session_id}         │
│        │                                                     │
│        ├── success → git diff 검증 → DONE                    │
│        ├── error   → 재시도 카운터 증가 → 백오프             │
│        └── partial → session_id 보존 → 다음 step enqueue     │
└──────────────────────────────────────────────────────────────┘
```

---

## 6. 자주 깨지는 지점

- **CWD 혼동** — `claude -p` 의 CWD 는 호출자 셸과 같다. `--add-dir` 로 명시하지 않으면 settings.json/CLAUDE.md 가 엉뚱한 디렉토리에서 로드됨
- **stdout 혼합** — 작업 자체의 출력과 `--output-format json` 결과가 섞임. 항상 별도 파일로 캡처
- **레이트 리밋** — 구독 플랜 한도. 멀티 큐에서 동시 N>1 으로 돌리면 쉽게 hit
- **OAuth 토큰 만료** — claude 호출 자체가 401. healthcheck 로 사전 탐지

---

## 다음

- [05 — Headless Ops](./05-headless-ops.md)
- [recipes/auto-coding-loop](../recipes/auto-coding-loop.md)
- [recipes/multi-agent-orchestration](../recipes/multi-agent-orchestration.md)

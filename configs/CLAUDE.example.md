# 프로젝트 컨텍스트 (Claude Code 용)

> 이 파일은 OpenClaw 가 작업을 시작할 때 Claude Code 에 컨텍스트로 주입하는 템플릿이다.
> 실제 사용 시 `CLAUDE.md` 로 복사하여 프로젝트 루트에 두면 Claude Code 가 자동 로드한다.

## 이 프로젝트의 정체

- 한 줄 설명: <서비스/리포 한 줄로 요약>
- 주 언어 / 프레임워크: <예: TypeScript + Next.js / Python + FastAPI>
- 배포 환경: <예: Vercel / 자체 K8s / Pi local>

## 디렉토리 가이드

- `src/` — 애플리케이션 소스
- `tests/` — 테스트
- `scripts/` — 운영 스크립트
- `docs/` — 문서

## 코드 컨벤션

- 들여쓰기: <2-space / 4-space>
- 포맷터: <prettier / black / gofmt>
- 린터: <eslint / ruff>
- 커밋: Conventional Commits 한글 (`feat:`, `fix:` ...)

## 테스트

- 단위 테스트: `<command>`
- 통합 테스트: `<command>`
- PR 머지 전 항상 통과되어야 함.

## 자주 쓰는 명령

```bash
# 개발 서버
<command>

# 린트 + 포맷
<command>

# 빌드
<command>
```

## 주의 사항 (반드시 지킬 것)

- DB 마이그레이션은 검토 없이 실행하지 말 것
- `.env`, `secrets/` 경로는 절대 읽거나 쓰지 말 것
- 외부 네트워크 호출은 명시적으로 허용된 호스트에 한함
- 작업 결과는 항상 새 브랜치에 커밋, 직접 main 푸시 금지

## OpenClaw 자율 작업 시 추가 규칙

- 작업이 5분 이상 걸리면 중간 진행 상황을 stdout 으로 출력
- 외부 인증이 필요한 단계가 발견되면 즉시 작업 중단 + 사용자 알림
- 비파괴 동작만 자동 진행, 파괴적 동작은 dry-run 후 큐에 confirm 작업 추가

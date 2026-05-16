# 프로젝트 컨텍스트 — github-pr-bot

GitHub 이슈를 작은 변경 PR 로 자동 변환하는 봇.

## 책임

- 입력: `automation:cleanup` 라벨이 붙은 열린 이슈 1건 (pick-issue.sh 가 선택)
- 출력: 새 브랜치 + 커밋 + PR (post-pr.sh 가 발행)
- main 직접 푸시 금지 — 항상 새 브랜치

## 절대 규칙

- **변경 라인 ≤ 30** — 큰 작업으로 보이면 즉시 중단 (종료 코드 2)
- **금지 경로**: `.github/`, `scripts/`, `*.lock`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`
- **금지 동작**: 의존성 추가/제거, 외부 네트워크 호출(curl/wget), force push, main 푸시
- **PR 본문**: 반드시 `Closes #<num>` 포함. LLM 출력 그대로 복사 시 민감정보 redaction 패스 필수

## 커밋 형식

```
fix(#<issue-number>): <한 줄 요약>
```

## 브랜치 명명

`bot/auto/<issue-number>` (PR_BOT_BRANCH_PREFIX 환경변수로 prefix 변경 가능)

## 자율 작업 시 추가 규칙

- 이슈 본문이 명확하지 않으면 추측하지 말고 종료 코드 2 (요청자가 본문 보강 후 재트리거)
- 테스트가 깨지면 작업 되돌리고 종료 코드 1
- 실행 시간 5분 초과 시 중간 진행 출력
- PR 라벨 `bot:auto` 자동 부여 (post-pr.sh)

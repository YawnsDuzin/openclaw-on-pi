# Example — github-pr-bot

> GitHub 이슈를 읽고 작은 변경 PR 을 자동 생성하는 봇 예제.

⏳ **상태: 스텁 (코드 미작성)**
구현은 실 저장소 + PAT 발급 + Pi 검증을 마친 뒤 별도 PR.

---

## 의도

- 라벨 `automation:cleanup` 이 붙은 닫힌 → 열린 이슈를 폴링
- 가장 단순한 1건을 골라:
  - 새 브랜치 `bot/auto/<issue-number>` 생성
  - 변경 적용 (Claude Code 가 수행)
  - 커밋 + 푸시 + PR 생성
  - PR 본문에 `Closes #<num>`
- main 직접 푸시 절대 금지

전체 시나리오 흐름은 [`recipes/auto-coding-loop`](../../recipes/auto-coding-loop.md) 와 동일하지만, 여기는 **재현 가능한 최소 코드 + 설정** 패키지.

---

## 예고된 디렉토리 구조

```
github-pr-bot/
├── README.md
├── tasks.yaml             ← cron schedule + payload 템플릿
├── CLAUDE.md              ← 봇 행동 규칙 (PR 형식, 금지 동작)
├── settings.example.json  ← gh CLI / git push 권한 화이트리스트
└── scripts/
    ├── pick-issue.sh      ← gh issue list 결과 중 1건 선택
    └── post-pr.sh         ← PR 생성 + 라벨링 helper
```

---

## 예고된 필요 환경

- `gh` CLI 설치 + 인증 (`gh auth login`)
- fine-grained PAT: `contents:write`, `pull_requests:write`
- 대상 저장소에 `automation:cleanup`, `bot:auto` 라벨 사전 생성
- 브랜치 보호 규칙: PR 머지에 사람 승인 1명 필수

---

## TODO (구현 시)

- [ ] PAT 안전 보관 위치 정립 (`~/.openclaw-secrets/github.env`, 권한 600)
- [ ] `pick-issue.sh` — JSON 파싱으로 단일 이슈 선택, 락(lock) 으로 중복 방지
- [ ] `tasks.yaml` 의 prompt — 변경 라인 수 / 영향 파일 수 상한 명시
- [ ] dry-run 모드 (PR 안 만들고 생성될 PR 본문만 출력)
- [ ] 첫 1주일 production-shadow 모드로 관찰 → 문제 없으면 활성화
- [ ] 실 저장소에서 1주 가동 후 본 README 갱신

---

## 보안 주의

- PR 본문에 LLM 출력이 그대로 들어가므로 **민감 토큰 패턴 redaction** 필수
- `gh pr create` 권한은 화이트리스트로만 노출 — `Bash(gh:*)` 같은 와일드카드 금지
- 봇이 만든 PR 은 사람 리뷰 없이 머지 금지 (브랜치 보호로 강제)

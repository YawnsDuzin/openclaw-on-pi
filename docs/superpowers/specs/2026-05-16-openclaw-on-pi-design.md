# openclaw-on-pi — 프로젝트 / 문서 작성 계획 (Design Spec)

작성일: 2026-05-16
상태: Approved (자율 진행 모드)
근거: 루트 `README.md` (커밋 `910e10a` 기준)

---

## 1. 배경 · 목표

`openclaw-on-pi` 는 라즈베리파이에서 **OpenClaw 자율 에이전트** 를 **Claude Code OAuth 구독** 으로 24/7 구동하는 실전 가이드 저장소다.
현재 상태는 README 에 명시된 대로 **blueprint** — 디렉토리 구조와 인덱스만 존재하고 실제 콘텐츠(문서·스크립트·설정·예제) 는 비어 있다.

본 스펙의 목표:

1. README 가 약속한 산출물을 **빠짐 없이, 일관된 톤** 으로 채운다.
2. 산출물을 **의존성 순서대로 단계화** 해서 부분 출시(partial release) 가 가능하게 한다.
3. 각 단계 종료 시점에 **외부 기여자가 따라할 수 있는** 수준의 완성도를 유지한다.

**비목표 (out of scope):**

- OpenClaw 자체의 코드 수정 / fork
- Claude Code CLI 자체의 코드 수정
- 웹 대시보드, GUI, SaaS 호스팅
- Pi Zero 2W / Pi 3 호환 (README 가 명시적으로 비권장)

---

## 2. 사용자 정의

| 페르소나 | 설명 | 기대 |
|---|---|---|
| **Pi 운영자** | Linux/Pi 경험 있음, Claude Pro/Max 구독자 | 한 번에 동작하는 셸 명령, 안전한 기본값 |
| **에이전트 개발자** | OpenClaw / Claude Code 통합에 관심 | 실전 레시피, 함정 포인트 |
| **보안 검토자** | 24/7 노출 디바이스의 위험을 먼저 봄 | OAuth/SSH/방화벽 가이드, 권한 모델 |

세 페르소나 모두 한국어를 1차 언어로 가정 (README 와 일치). 영문화는 README 로드맵의 후속 작업.

---

## 3. 핵심 설계 원칙

1. **README 가 단일 진실 공급원** — 디렉토리 구조 / 인덱스는 README 에 기재된 것을 따른다. 변경 시 README 와 함께 업데이트.
2. **재현성 > 완벽함** — `bash scripts/X.sh` 한 줄로 끝나야 한다. 수동 단계는 번호 매긴 리스트로.
3. **의견(opinion) 있는 기본값** — "원하는대로 고르세요" 대신 권장값 1개 제시 + 대안은 각주.
4. **방어적 셸 스크립트** — `set -euo pipefail`, idempotent (재실행 안전), 실패 시 명확한 메시지.
5. **보안 우선** — 토큰/키는 절대 커밋 금지. 예제는 `.example.*` 접미사. 실제 파일은 `.gitignore`.
6. **검증할 수 없는 주장 금지** — Pi 하드웨어 없이 작성하므로, 미검증 부분은 "검증 필요 (untested on hardware)" 배지로 표시.

---

## 4. 단계 분해 (Phased Plan)

각 단계는 단독으로 커밋 가능하며, 다음 단계는 이전 단계 산출물에 의존한다.

### Phase 1 — 저장소 토대 (Foundation)

산출물:

- `LICENSE` (MIT, README 와 일치)
- `.gitignore` (Node, Python, OS, 토큰/시크릿 패턴)
- `.editorconfig` (LF, UTF-8, 4-space for sh / 2-space for yaml/json/md)
- `.github/ISSUE_TEMPLATE/bug.yml`
- `.github/ISSUE_TEMPLATE/recipe-request.yml`
- `.github/workflows/lint-markdown.yml` (markdownlint-cli2)
- `configs/openclaw.example.yaml` (작업 큐 / 워커 / 출력 경로 예시)
- `configs/claude-code-settings.example.json` (도구 권한 화이트리스트, 모델 핀)
- `configs/CLAUDE.example.md` (OpenClaw 가 참조할 컨텍스트 템플릿)
- `configs/systemd/openclaw.service`
- `configs/systemd/openclaw-watchdog.service`

수용 기준:

- `git clone` 후 lint 워크플로 통과
- 모든 `*.example.*` 파일은 안전한 더미값만 포함
- systemd 유닛은 `systemd-analyze verify` 통과 (포맷 정합)

### Phase 2 — 부트스트랩 / 운영 스크립트

산출물:

- `scripts/bootstrap-pi.sh` — apt 패키지, Node LTS (NodeSource), Python venv, tmux/jq/git
- `scripts/install-claude-code.sh` — npm 글로벌 설치, 버전 핀, PATH 검증
- `scripts/install-openclaw.sh` — OpenClaw 설치 (pip 또는 git clone — README 가 명시 안 했으므로 양쪽 분기)
- `scripts/oauth-tunnel.sh` — `ssh -R` 역포트포워딩, 사용법 출력
- `scripts/healthcheck.sh` — claude / openclaw / 디스크 / 메모리 / 토큰 만료 체크, 종료코드로 OK/FAIL

공통 규칙:

- 셔뱅 `#!/usr/bin/env bash`
- `set -euo pipefail`
- 색상 출력 (`tput setaf`) — TTY 가 아니면 자동 비활성화
- 모든 스크립트 상단에 1줄 USAGE 주석
- 파괴적 액션은 `--dry-run` 지원 또는 confirm 프롬프트

수용 기준:

- `shellcheck scripts/*.sh` 통과 (warning 0, info 무시 허용)
- 두 번 실행해도 동일한 결과 (idempotent)

### Phase 3 — 코어 문서 (01-06 + troubleshooting)

산출물:

- `docs/01-prerequisites.md` — HW(Pi 4/5, NVMe, 쿨링), OS(RPiOS 64-bit, Ubuntu Server), 네트워크/전원/패키지 체크리스트
- `docs/02-claude-code-oauth.md` — 헤드리스 OAuth 의 본질(브라우저 콜백 필요), SSH 포트포워딩 트릭 단계별, 토큰 위치/권한, 만료 대응
- `docs/03-openclaw-install.md` — 설치 / 설정 / 첫 실행 / 작업 큐 정의 예
- `docs/04-integration.md` — OpenClaw → Claude Code 호출 패턴, CLAUDE.md 역할, 권한 화이트리스트
- `docs/05-headless-ops.md` — tmux 세션, systemd 유닛, 로그 수집(journald → 파일 회전), 원격 SSH/VPN
- `docs/06-performance-tuning.md` — ARM64 휠 빌드, zram/NVMe 스왑, 쿨링/거버너, 모델 선택(Sonnet/Haiku)
- `docs/troubleshooting.md` — OAuth 실패, 토큰 만료, OOM, 빌드 휠 부재, systemd 재시작 루프 등

문서 공통:

- 첫 줄 H1 = 파일명과 일치
- 그 아래 1줄 요약 + 사전 조건 박스
- "✅ 검증 환경" / "⚠ 미검증" 배지 사용
- 예제 명령은 즉시 복붙 가능해야 함 (placeholder 는 `<...>`)

수용 기준:

- 모든 문서 간 상대링크 깨짐 0
- markdownlint 통과

### Phase 4 — 레시피 (5개)

산출물:

- `recipes/auto-coding-loop.md`
- `recipes/remote-vibe-coding.md`
- `recipes/scheduled-agent-tasks.md`
- `recipes/multi-agent-orchestration.md`
- `recipes/iot-bridge.md`

레시피 공통 템플릿:

```
# 제목
> 한 줄 목적

## 시나리오
## 필요 조건
## 단계
## 운영 팁
## 알려진 한계
```

### Phase 5 — 예제 프로젝트 (HW 검증 필요)

`examples/hello-agent/`, `examples/github-pr-bot/`, `examples/log-triage/` 는 **실제 코드까지 작성하면 Pi 하드웨어 + OAuth 토큰 + GitHub repo** 가 모두 필요하다. 이 세션에서는 다음만 만든다:

- 각 디렉토리에 `README.md` 스텁 — 의도, 입력/출력, 디렉토리 구조 예고, "TODO: implement" 표시
- 실제 구현은 별도 PR 단위로 분리 (각 예제마다 1 PR)

이렇게 분리하는 이유: 동작 검증 없이 코드를 커밋하면 사용자 입장에서 가짜 자산이 된다. 스텁만 두면 README 인덱스의 약속은 지키되 사용자가 잘못된 코드를 신뢰하지 않는다.

### Phase 6 — README 동기화

- README 의 "문서 인덱스" / "레시피" 섹션에 **상태 마커** 추가:
  - `✅` = 완성 · 검증
  - `⚠` = 작성 완료 · HW 미검증
  - `⏳` = 스텁 · 미작성
- 모든 상대링크가 실제 파일을 가리키는지 검증
- "로드맵" 체크박스 갱신

---

## 5. 컨벤션

| 항목 | 규칙 |
|---|---|
| 파일 인코딩 | UTF-8, LF |
| 마크다운 들여쓰기 | 2-space |
| 셸 들여쓰기 | 4-space, no tabs |
| YAML/JSON 들여쓰기 | 2-space |
| 커밋 메시지 | Conventional Commits 한글 (`docs:`, `feat:`, `chore:` ...) |
| 이슈 라벨 | `bug`, `recipe`, `docs`, `script`, `security` |
| 스크립트 셔뱅 | `#!/usr/bin/env bash` |
| 문서 1차 언어 | 한국어 |
| 토큰/시크릿 | 절대 커밋 금지 — `.example.*` 접미사로만 |

---

## 6. 위험 · 가정

**가정 (assumption):**

- OpenClaw 의 정확한 설치 절차 / CLI 인터페이스는 README 가 가리키는 외부 프로젝트를 따른다. 본 저장소는 **wrapper / guide** 로서 명령 형태가 다르더라도 구조가 살아남도록 추상화한다.
- Claude Code CLI 의 `claude login`, `~/.claude/` 토큰 위치, `settings.json` 권한 모델은 현재 안정 버전 기준.
- 사용자는 Pro 또는 Max 구독자 (Free 는 README 에서 부적합으로 명시).

**위험 (risk):**

- **R1**: 작성 환경이 Windows 라 셸 스크립트 / Pi OS 명령을 실행 검증할 수 없다. → `shellcheck` 정적 분석으로 보완, "✅/⚠" 배지 명시.
- **R2**: OpenClaw / Claude Code 의 후속 릴리스가 인터페이스를 바꾸면 문서가 빠르게 stale 된다. → 각 문서 상단에 "검증 시점" 메타 표기.
- **R3**: OAuth 토큰 자동 갱신은 Anthropic 측 API 미공개 영역. README 로드맵에도 미해결로 남아 있음 → 본 스펙도 **수동 재인증 절차 + 모니터링** 만 다루고, 자동 갱신은 별도 RFC 로 미룬다.

---

## 7. 산출물 체크리스트

- [ ] Phase 1 — 저장소 토대 (12 파일)
- [ ] Phase 2 — 스크립트 5개
- [ ] Phase 3 — 코어 문서 7개
- [ ] Phase 4 — 레시피 5개
- [ ] Phase 5 — 예제 스텁 3개
- [ ] Phase 6 — README 동기화 + 링크 검증

각 Phase 완료 시 1 커밋, 마지막에 `MEMORY.md` / 상태 라벨 갱신.

---

## 8. 후속 (이번 세션 밖)

- 영문 README / 문서 페어 (README 로드맵 항목)
- OAuth 토큰 자동 갱신 RFC
- 멀티 에이전트 큐 매니저 설계
- Pi 5 NPU HAT 활용 검토
- examples/ 내 실제 코드 구현 + Pi 검증

이상.

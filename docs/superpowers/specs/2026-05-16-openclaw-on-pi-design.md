# openclaw-on-pi — 프로젝트 / 문서 작성 계획 (Design Spec)

작성일: 2026-05-16
상태: 1차 라운드 폐기 → **2차 라운드 (재작성) 진행 중 (2026-05-16~17)**
근거: 루트 `README.md` (원안: 커밋 `910e10a`) + 공식 [openclaw/openclaw GitHub](https://github.com/openclaw/openclaw) + [docs.openclaw.ai](https://docs.openclaw.ai/) (2차 라운드 시 확인)

> 🚨 **중대 정정 (2026-05-17)**: 1차 라운드는 OpenClaw 의 정체를 **잘못 가정** 한 상태로 작성되었음.
>
> - 1차 가정: Python/pip 기반 자율 작업 큐 프레임워크, `openclaw run/enqueue` CLI, `tasks.yaml` 스키마, Claude Code 에 코드 작성 위임
> - 사실: TypeScript/Node.js, 메시징 채널 게이트웨이, `openclaw onboard/gateway/agent/message` CLI, SKILL.md 기반, BYOK 다중 모델 라우팅 (Claude Code 와는 무관한 별 인증 경로). 최초 공개 2025-11-24 (Peter Steinberger). 2026-03 GitHub 1위 (스타 ~370K). Steinberger 2026-02-14 OpenAI 합류.
>
> PyPI 의 `openclaw` 패키지는 cmdop.com 의 별 SDK 플러그인이며 본 프로젝트와 무관. 1차 라운드 사용자가 Pi 에서 `bash scripts/install-openclaw.sh` (pip 모드) → CLI 미존재 → 추적으로 잘못된 청사진을 발견.
>
> 본 문서의 Phase 1–6 산출물은 2차 라운드에서 대부분 재작성됨. [[project-openclaw-facts]] / [[project-openclaw-security]] 메모리 참고.

> 📌 1차 라운드 (2026-05-16) 실행 결과 — 참고용으로 보존:
> - **Phase 3**: `docs/00-quickstart.md` 한 페이지 가이드 추가 (총 7 → 8 문서)
> - **Phase 5**: examples 를 *스텁만* 두려던 원안에서 **best-effort 코드 작성(⚠)** 로 정책 변경
>
> 모든 1차 산출물 마커는 ⚠ 였고, 2차 라운드에서 다음과 같이 재구성:

---

## 1. 배경 · 목표

`openclaw-on-pi` 는 라즈베리파이에서 **OpenClaw 자율 에이전트** 를 **Claude Code OAuth 구독** 으로 24/7 구동하는 실전 가이드 저장소다.
원안 시점(커밋 `910e10a`)에는 README 디렉토리 구조와 인덱스만 존재하는 **blueprint** 상태였고, 본 스펙은 그 안을 채우는 단계별 계획으로 작성되었다.
2026-05-16 실행 결과 docs / scripts / configs / recipes / examples 모두 **1차 작성 완료(⚠ 마커)** — 다음 라운드는 Pi HW 검증.

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

### Phase 3 — 코어 문서 (00-quickstart + 01-06 + troubleshooting)

산출물:

- `docs/00-quickstart.md` — **처음 사용자용 한 페이지 절차** (Phase 1→4, 약 1시간). 각 단계에 검증 명령 + 실패 시 점프 위치 명시. *원안 이후 추가됨*
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

### Phase 5 — 예제 프로젝트 (정책 변경: 스텁 → best-effort 코드 ⚠)

**원안**: 각 예제는 README 스텁만 두고 실제 코드는 별도 PR 로 분리.
**실행 결과**: 정적 리뷰만으로 안전성 검증 가능한 범위에서 **best-effort 코드를 작성하고 ⚠ 마커** 로 표시. 활성화 절차에 dry-run / 그림자 가동을 강제하여 가짜 자산 위험을 완화.

산출물:

- `examples/hello-agent/` — 최소 동작 검증. `tasks.yaml` + `CLAUDE.md` + `run.sh`. 성공 시 README.md 끝에 1줄 추가 + 1 커밋
- `examples/github-pr-bot/` — 이슈 → PR 자동화. `tasks.yaml` + `CLAUDE.md` + `settings.example.json` (도구 화이트리스트) + `scripts/pick-issue.sh` + `scripts/post-pr.sh`. 첫 가동 시 dry-run 1주일 그림자 가동 권장
- `examples/log-triage/` — journald 로그 LLM 트리아지. `tasks.yaml` + `CLAUDE.md` + `prompts/triage.md` + `scripts/collect-logs.sh` (마스킹 룰셋 포함) + `scripts/publish.sh`. 첫 가동 시 `LOG_TRIAGE_PUBLISH=stdout` 으로 1주일 그림자 가동 후 채널 라우팅 활성화

공통 안전 장치:

- 모든 예제 README 상단에 ⚠ "Pi 미검증" 배지 + 활성화 전 dry-run/shadow 지침
- 권한 화이트리스트(`settings.example.json`)로 셸·네트워크 도구 deny 우선
- 파괴적 git 명령 금지를 `CLAUDE.md` 절대 규칙에 명시

수용 기준:

- `shellcheck examples/**/*.sh` 통과
- Pi 검증 후 README 의 예제 마커 ⚠ → ✅ 일괄 승격

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

- [x] Phase 1 — 저장소 토대 (LICENSE, .gitignore, .editorconfig, 이슈 템플릿 2, lint 워크플로, configs 5)
- [x] Phase 2 — 스크립트 5개 (bootstrap-pi, install-claude-code, install-openclaw, oauth-tunnel, healthcheck)
- [x] Phase 3 — 코어 문서 8개 (00-quickstart + 01–06 + troubleshooting)
- [x] Phase 4 — 레시피 5개 (auto-coding-loop, remote-vibe-coding, scheduled-agent-tasks, multi-agent-orchestration, iot-bridge)
- [x] Phase 5 — 예제 3개 (hello-agent / github-pr-bot / log-triage) — *원안 스텁 → best-effort 코드 작성* (⚠)
- [x] Phase 6 — README 동기화 + 상태 마커 + 로드맵 갱신

전 Phase 1차 라운드 완료(2026-05-16). **단, 다음 Pi 실행에서 OpenClaw 의 정체 가정 오류 발견 → 2차 라운드로 재작성.**

---

## 7-bis. 2차 라운드 (재작성, 2026-05-16~17)

**근거**: 1차 라운드의 가정 ↔ 공식 [openclaw/openclaw](https://github.com/openclaw/openclaw) 차이가 너무 커서 사용자가 따라할 수 있는 가이드가 못 됨. PyPI `openclaw` 도 무관한 별 프로젝트로 판명.

**산출물**:

- [x] **scripts/install-openclaw.sh** — pip/pipx 모드 폐기 → `npm install -g openclaw@latest`. Node 22+ 검증, 최소 안전 버전 2026.2.6 (CVE-2026-25253 패치) 비교
- [x] **scripts/bootstrap-pi.sh** — `NODE_MAJOR` 20 → 22 (OpenClaw 최소 22.16 요구)
- [x] **configs/openclaw.example.json5** (신규, .yaml 폐기) — 실제 OpenClaw 설정 포맷 (JSON5). loopback 바인딩 + token 인증 + Telegram pairing 권장
- [x] **docs/03-openclaw-install.md** — `openclaw onboard` 흐름, 두 인증 경로 (Claude Code OAuth vs ~/.openclaw API key) 명시
- [x] **docs/04-integration.md** — "Claude Code 위임" 가정 제거, BYOK 라우팅 + SKILL.md 매칭으로
- [x] **docs/00-quickstart.md Phase 3** — onboard → gateway → pair → hello-agent 흐름
- [x] **docs/07-openclaw-hardening.md** (신규) — CVE 인벤토리, gateway 베이스라인, reverse-proxy 절차, ClawHub 스킬 리뷰 체크리스트, 사고 대응
- [x] **README.md** — 아키텍처 그림 (메시징 게이트웨이), 보안 섹션 (CVE / Cisco), 알려진 제약, 로드맵 1차→2차 라운드 기록
- [x] **examples/{hello-agent, github-pr-bot, log-triage}** — SKILL.md frontmatter + 본문 + bundled scripts 패턴으로 재작성. `tasks.yaml` / Claude Code `CLAUDE.md` / `settings.json` 폐기
- [x] **recipes/5개** — `openclaw enqueue/run` 가상 명령 폐기, OpenClaw `cron.jobs` + systemd timer + `openclaw agent --skill X` 실제 인터페이스
- [x] **본 spec** — 1차 폐기 / 2차 산출물 기록
- [ ] **MEMORY**: [[project-openclaw-facts]] / [[project-openclaw-security]] 갱신 (완료)

**남은 작업**:

- 정합성 점검 (troubleshooting.md 의 1차 가정 잔존, 05-headless-ops.md 의 /opt/openclaw systemd 가정 등) — Task #16
- Pi 5 실 환경에서 onboard → gateway → hello-agent 끝-끝 검증
- examples 3종 1주 그림자 가동 → ✅ 승격

---

## 8. 후속 (이번 세션 밖)

- **Pi 5 (8GB) 실 환경 끝-끝 검증** (다음 라운드 1순위) — bootstrap → install-openclaw → onboard → gateway → hello-agent 통과 시 docs/scripts/configs/recipes 마커 ⚠ → ✅
- github-pr-bot `PR_BOT_DRY_RUN=1` 1주일 production-shadow → 활성화
- log-triage `LOG_TRIAGE_PUBLISH=stdout` 1주일 그림자 → 마스킹 룰셋 보강 + 채널 활성화
- ClawHub 스킬 외부 도입 시 [docs/07 §4](../../07-openclaw-hardening.md#4-스킬-clawhub-안전-정책) 리뷰 체크리스트 사례화
- Cisco *DefenseClaw* 등 외부 보안 도구 연계 가이드
- 영문 README / 문서 페어 (README 로드맵 항목)
- BYOK 토큰 자동 갱신 / 회전 절차 RFC
- Pi 5 NPU HAT 활용 검토 (로컬 모델 실험)

## 9. 교훈 (1차 → 2차 라운드)

- **확인 가능한 가정만 코드로 옮길 것**: OpenClaw 처럼 변화가 빠르고 정체가 모호한 외부 프로젝트를 wrap 할 때는 공식 docs / GitHub 를 *처음* 에 확인해야 한다. 1차 라운드는 "README 청사진" 만으로 모든 산출물을 짰고, 결과적으로 사용자가 따라할 수 없는 가이드를 만들었다.
- **검증 가능한 마커**: ⚠ 마커가 의도대로 동작 — 사용자가 Pi 에서 실행 시 즉시 차이를 발견. 만약 1차 산출물을 ✅ 로 잘못 표기했다면 더 큰 시간 낭비 발생.
- **메모리에 사실관계 박기**: 본 라운드 종료 후 [[project-openclaw-facts]] / [[project-openclaw-security]] 를 메모리에 보존 — 다음 세션이 같은 함정을 다시 빠지지 않게.

이상.

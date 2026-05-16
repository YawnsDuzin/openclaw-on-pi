# openclaw-on-pi

> 라즈베리파이에서 **OpenClaw 자율 에이전트**를 **Claude Code (OAuth 구독)** 로 24/7 구동하는 실전 가이드.
> API 키 없이 Pro/Max 구독만으로 엣지 디바이스에서 에이전트를 돌린다.

![Raspberry Pi](https://img.shields.io/badge/Raspberry%20Pi-4%2F5-c51a4a)
![Claude Code](https://img.shields.io/badge/Claude%20Code-OAuth-d97706)
![OpenClaw](https://img.shields.io/badge/OpenClaw-autonomous--agent-6366f1)
![Status](https://img.shields.io/badge/status-WIP%20·%20blueprint-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

> ⚠️ **프로젝트 상태: WIP (문서 / 스크립트 / 예제 코드 1차 작성 완료, HW 검증 대기)**
> 핵심 문서·설정·셸 스크립트·예제 코드까지 모두 best-effort 로 작성되었습니다 (한국어). 다음 단계는 Pi 5 실 환경에서 부트스트랩 → OAuth → hello-agent 까지 끝-끝 검증입니다.
> 각 항목의 상태는 [문서 인덱스](#문서-인덱스) · [레시피](#레시피) · [예제](#예제) 의 마커(✅/⚠/⏳) 를 보세요. 이슈·PR 환영합니다.
>
> **상태 마커 범례**:
> ✅ 작성 완료 + Pi 에서 검증 ・ ⚠ 작성 완료, HW 미검증 (정적 리뷰만 통과) ・ ⏳ 스텁 / 미작성

---

## 왜 이걸 만드는가

- 데스크탑/노트북 켜둘 필요 없이 **Pi 한 대로 자율 에이전트 상시 가동**
- **BYOK 다중 모델 라우팅** — Anthropic / OpenAI / Google / Local 어느 쪽이든. Claude Pro/Max 구독자는 Claude Code CLI (vibe-coding) 를 같이 두면 두 도구 결합 효과
- 엣지에서 GitHub PR 자동화, 로그 트리아지, IoT 모니터링 등 백그라운드 작업
- **데이터 주권**: 세션·메시지·스킬·로그·자격증명을 클라우드 아닌 개인 디바이스에 보관

## OpenClaw 가 뭔가요?

[`OpenClaw`](https://github.com/openclaw/openclaw) 는 Peter Steinberger (PSPDFKit 창업자) 가 만든 **오픈소스 자체 호스팅 자율 AI 에이전트** 입니다. 메시징 플랫폼 (Telegram / WhatsApp / Slack / Discord / iMessage 등 22+) 을 메인 UI 로, 채팅 앱에 말 걸듯 에이전트를 부립니다. TypeScript / Node.js, MIT 라이선스. 2025-11 첫 공개 (Clawdbot → Moltbot → OpenClaw), 2026-03 GitHub 스타 25만 돌파.

본 가이드는 그 OpenClaw 를 **Raspberry Pi 에서 24/7 헤드리스로 안전하게** 띄우는 절차를 다룹니다. OpenClaw 는 BYOK 다중 모델 라우팅이라 **Anthropic Claude / OpenAI / Google / Local** 어느 쪽이든 사용 가능하며, 본 가이드의 권장 기본값은 Anthropic Claude (Pro/Max 구독자가 1차 사용자) 입니다.

> 🚨 **보안 사전 공지**: OpenClaw 는 24/7 자율 셸 실행 + 외부 메시징 채널 + 자가 스킬 작성 조합으로 노출 면적이 매우 큽니다. 공개된 위험 (CVE-2026-25253 / reverse-proxy 인증 우회 93.4% / ClawHub 악성 스킬 230+ / Cisco 보고서) 을 [`docs/07-openclaw-hardening.md`](docs/07-openclaw-hardening.md) 에 정리했으니 운영 전 반드시 통독하세요.

> 📌 설치·구성은 [`docs/03-openclaw-install.md`](docs/03-openclaw-install.md). 첫 끝-끝 검증은 [`docs/00-quickstart.md`](docs/00-quickstart.md).

## 처음 사용자라면

> 👉 **[`docs/00-quickstart.md`](docs/00-quickstart.md)** 한 페이지를 위에서 아래로 따라가세요. 빈 Pi → 24/7 가동까지 약 1시간, 단계마다 검증 명령과 실패 시 점프 위치가 명시되어 있습니다.

## TL;DR (요약 — 자세한 절차는 quickstart 참고)

```bash
# 0) 작업 베이스 디렉토리 (모든 단계 공통 — 사용자 dzp 기준)
mkdir -p /home/dzp/dzp_main/program
cd /home/dzp/dzp_main/program

# 1) 본 가이드 저장소 클론 + Pi 부트스트랩 (Node 22+, 핵심 apt 패키지)
git clone https://github.com/YawnsDuzin/openclaw-on-pi.git
cd /home/dzp/dzp_main/program/openclaw-on-pi
bash scripts/bootstrap-pi.sh

# 2) (선택) Claude Code CLI — vibe-coding 용. OpenClaw 의 모델 호출과는 별도.
bash scripts/install-claude-code.sh
export PATH="$HOME/.npm-global/bin:$PATH"
# OAuth 1회: bash scripts/oauth-tunnel.sh → 로컬 PC 에서 SSH -L → claude login

# 3) OpenClaw 설치 + 대화형 온보딩 (BYOK 토큰 / 채널 / Gateway)
bash scripts/install-openclaw.sh
openclaw onboard --install-daemon

# 4) Gateway 띄우고 hello 스킬로 끝-끝 검증
openclaw gateway --port 18789 --verbose &        # 백그라운드 또는 별도 tmux 창
cp -r examples/hello-agent /home/dzp/dzp_main/program/openclaw-work/ \
  && cd /home/dzp/dzp_main/program/openclaw-work/hello-agent
bash run.sh                                       # SKILL.md 설치 + agent --message "hello"

# 5) 헬스체크
bash /home/dzp/dzp_main/program/openclaw-on-pi/scripts/healthcheck.sh
```

> 📁 **경로 규약**: 본 가이드는 `/home/dzp/dzp_main/program/` 을 가이드 저장소 + 사용자 워크스페이스 베이스로 사용합니다. OpenClaw 자체의 상태/스킬/자격증명은 별도로 `~/.openclaw/` 하위에 둡니다 (OpenClaw 기본 동작 — 두 경로의 역할이 다릅니다).
>
> 🚨 **운영 전 필독**: [`docs/07-openclaw-hardening.md`](docs/07-openclaw-hardening.md) — CVE 인벤토리, gateway 보안 베이스라인, ClawHub 스킬 리뷰 체크리스트.

> 헤드리스 환경에서 OAuth 브라우저 콜백을 받는 방법은 [`docs/02-claude-code-oauth.md`](docs/02-claude-code-oauth.md) 참고.

---

## 사전 지식

본 가이드는 다음을 전제로 합니다.

- Linux 셸 기본 (`ssh`, `systemd`, `cron`, `tmux`)
- Raspberry Pi OS 또는 Ubuntu Server 설치·플래싱 경험
- **BYOK 모델 자격증명 1개 이상** (OpenClaw 가 호출). 본 가이드 권장: Anthropic API key (console.anthropic.com 에서 발급). 단, **Claude Pro/Max 구독은 OpenClaw 가 *직접 쓰지 않는다*** — 구독은 Claude Code CLI 의 OAuth 용 (vibe-coding). 비용 구조는 [비용 · 전력 가늠](#비용--전력-가늠) 참고
- Git / GitHub 사용 경험

---

## 디렉토리 구조

```
openclaw-on-pi/
├── README.md
├── LICENSE
├── .gitignore
├── .editorconfig
│
├── docs/                             # 학습 순서대로 번호 부여
│   ├── 00-quickstart.md              # 처음 사용자 — 위에서 아래로 약 1시간
│   ├── 01-prerequisites.md           # Pi 하드웨어, OS, 네트워크, 패키지
│   ├── 02-claude-code-oauth.md       # 헤드리스 Claude Code OAuth (vibe-coding 용)
│   ├── 03-openclaw-install.md        # OpenClaw 설치 (npm) · onboard · 첫 동작
│   ├── 04-integration.md             # BYOK 라우팅, Claude Code 와의 관계
│   ├── 05-headless-ops.md            # tmux, systemd, 원격 운용, 로그 수집
│   ├── 06-performance-tuning.md      # ARM64, 스왑, NVMe, 쿨링
│   ├── 07-openclaw-hardening.md      # CVE / gateway 보안 / 스킬 리뷰 / 사고 대응
│   └── troubleshooting.md            # 자주 깨지는 지점들
│
├── recipes/                          # 시나리오별 활용 레시피
│   ├── auto-coding-loop.md           # 자율 코딩 루프 24/7
│   ├── remote-vibe-coding.md         # 외부에서 Pi 에이전트 조작
│   ├── scheduled-agent-tasks.md      # cron + 에이전트
│   ├── multi-agent-orchestration.md  # 여러 OpenClaw 인스턴스 분업
│   └── iot-bridge.md                 # 에이전트가 IoT 센서/GPIO 다루기
│
├── scripts/
│   ├── bootstrap-pi.sh               # 환경 구축 원샷
│   ├── install-claude-code.sh
│   ├── install-openclaw.sh
│   ├── oauth-tunnel.sh               # SSH 포트포워딩으로 OAuth 콜백 받기
│   └── healthcheck.sh
│
├── configs/
│   ├── openclaw.example.json5        # OpenClaw 설정 (JSON5) — ~/.openclaw/openclaw.json
│   ├── claude-code-settings.example.json
│   ├── CLAUDE.example.md             # Claude Code 가 참조할 컨텍스트 템플릿
│   └── systemd/
│       ├── openclaw.service
│       └── openclaw-watchdog.service
│
├── examples/
│   ├── hello-agent/                  # 최소 동작 예제
│   ├── github-pr-bot/                # 이슈 → PR 자동화
│   └── log-triage/                   # 로그 분석 에이전트
│
├── assets/
│   └── images/
│
└── .github/
    ├── ISSUE_TEMPLATE/
    │   ├── bug.yml
    │   └── recipe-request.yml
    └── workflows/
        └── lint-markdown.yml
```

---

## 요구 사양

| 항목 | 권장 | 최소 |
|---|---|---|
| 보드 | Raspberry Pi 5 (8GB) | Pi 4 (4GB) |
| OS | Raspberry Pi OS 64-bit (Bookworm) | Ubuntu Server 24.04 ARM64 |
| 저장소 | NVMe SSD (PCIe HAT) | microSD A2 64GB+ |
| 디스크 여유 | 32GB 이상 | 16GB |
| 쿨링 | 액티브 쿨러 필수 (Pi 5 기준) | - |
| 네트워크 | 유선 이더넷 | 안정 Wi-Fi |
| 전원 | 공식 27W USB-C PD | 5V/3A 이상 |

> 🚫 **Pi Zero 2W / Pi 3 비권장**: ARM64 빌드 호환성, RAM, 발열 한계로 Node 22+ 런타임 + OpenClaw gateway + LLM 호출 워크로드를 안정 운용하기 어렵습니다.

---

## 핵심 컨셉

```
┌─────────────────────────────────────────────────────────────┐
│                  Raspberry Pi (24/7)                        │
│                                                             │
│   ┌─────────────────┐                                       │
│   │  OpenClaw       │  ── gateway 127.0.0.1:18789 (loopback)│
│   │  (Node 22+)     │  ── workspace ~/.openclaw/workspace   │
│   │                 │  ── skills    ~/.openclaw/skills/*    │
│   └────┬──────┬─────┘     (SKILL.md frontmatter + body)     │
│        │      │                                             │
│   ┌────▼──┐  ┌▼──────────────┐   ┌─────────────────────┐    │
│   │ BYOK  │  │ Channels      │   │ Claude Code CLI     │    │
│   │ 모델   │  │ (Telegram/    │   │ (선택, vibe-coding) │   │
│   │ 라우팅│  │  Discord/...) │   │ ~/.claude/creds     │    │
│   └───┬───┘  └────┬──────────┘   └────────┬────────────┘    │
└───────┼───────────┼──────────────────────-┼────────────────-┘
        ▼           ▼                       ▼
   Anthropic /   메시징 플랫폼          Anthropic (별도 OAuth,
   OpenAI / ...                          본 저장소 가이드의 대화형용)
```

**두 가지 인증 경로** 가 공존:

- `~/.openclaw/openclaw.json` — OpenClaw 가 BYOK 다중 모델 라우팅에 사용 (Anthropic API key 또는 다른 provider)
- `~/.claude/credentials.json` — Claude Code CLI 가 별도로 사용 (사람이 직접 `claude` 명령으로 vibe-coding 할 때)

OpenClaw 의 *주* 인터페이스는 **메시징 채널**: 사용자가 Telegram/Discord 봇에 메시지 → OpenClaw 가 적합한 스킬 매칭 (XML 시스템 프롬프트 주입 또는 슬래시 명령) → 도구 (셸/파일/브라우저/세션) 사용 → 결과를 채널로 회신.

---

## 문서 인덱스

| # | 문서 | 상태 | 내용 |
|---|---|:-:|---|
| 00 | [**Quickstart**](docs/00-quickstart.md) | ⚠ | **처음 사용자 — 위에서 아래로** (Phase 1→4, 약 1시간) |
| 01 | [Prerequisites](docs/01-prerequisites.md) | ⚠ | HW · OS · 패키지 |
| 02 | [Claude Code OAuth](docs/02-claude-code-oauth.md) | ⚠ | 헤드리스 OAuth 인증 트릭 |
| 03 | [OpenClaw Install](docs/03-openclaw-install.md) | ⚠ | 설치 · 설정 · 첫 실행 |
| 04 | [Integration](docs/04-integration.md) | ⚠ | 두 도구 엮기 |
| 05 | [Headless Ops](docs/05-headless-ops.md) | ⚠ | tmux · systemd · 원격 |
| 06 | [Performance](docs/06-performance-tuning.md) | ⚠ | ARM64 · 스왑 · NVMe |
| 07 | [**OpenClaw Hardening**](docs/07-openclaw-hardening.md) | ⚠ | **CVE · gateway 보안 · 스킬 리뷰 · 사고 대응 (운영 전 필독)** |
| ⚠ | [Troubleshooting](docs/troubleshooting.md) | ⚠ | 자주 깨지는 지점들 |
| 📋 | [설계 / 작성 계획](docs/superpowers/specs/2026-05-16-openclaw-on-pi-design.md) | ✅ | 본 저장소의 단계별 작성 plan |

---

## 레시피

| 상태 | 레시피 |
|:-:|---|
| ⚠ | [자율 코딩 루프 24/7](recipes/auto-coding-loop.md) |
| ⚠ | [외부에서 Pi 에이전트 조작 (Remote vibe-coding)](recipes/remote-vibe-coding.md) |
| ⚠ | [cron 기반 스케줄 작업](recipes/scheduled-agent-tasks.md) |
| ⚠ | [멀티 에이전트 오케스트레이션](recipes/multi-agent-orchestration.md) |
| ⚠ | [IoT 브릿지 — GPIO / MQTT 다루기](recipes/iot-bridge.md) |

### 예제

| 상태 | 예제 |
|:-:|---|
| ⚠ | [hello-agent](examples/hello-agent/) — 끝-끝 최소 동작 (SKILL.md + run.sh, 결정적 응답 검증) |
| ⚠ | [github-pr-bot](examples/github-pr-bot/) — 이슈 → PR 자동화 SKILL.md (`/cleanup-issue` 슬래시 명령 + cron) |
| ⚠ | [log-triage](examples/log-triage/) — journald 로그 LLM 트리아지 SKILL.md (마스킹 + 채널 라우팅 + 패턴 캐시) |

> 예제 모두 best-effort 작성 완료. 실 Pi 검증 후 ✅ 로 승격.
> github-pr-bot / log-triage 는 첫 가동 시 반드시 dry-run / `LOG_TRIAGE_PUBLISH=stdout` 으로 1주일 그림자 가동.

---

## 보안 · 운영 주의사항

24/7 가동되는 Pi 는 곧 **상시 인터넷 노출 자산** + **자율 셸 실행 + 외부 메시징 채널 + 자가 스킬 작성 면** 입니다. 일반적인 Pi 운영 위생 + **OpenClaw 특화 위험** 둘 다 고려해야 합니다.

### OpenClaw 특화 (필독 — 상세는 [`docs/07-openclaw-hardening.md`](docs/07-openclaw-hardening.md))

- **버전 핀**: OpenClaw ≥ **2026.2.6** (CVE-2026-25253 CVSS 8.8 패치 + VirusTotal 스캐너 포함)
- **Gateway 바인딩**: `gateway.host: "127.0.0.1"` + `gateway.bind: "loopback"` 강제. 외부 노출 인스턴스의 **약 93.4%** 가 reverse-proxy 인증 우회에 노출
- **자격증명 평문 저장**: `~/.openclaw/` 하위가 평문 → 디렉토리 `700`, 백업 별도 분리, 침해 시 토큰 즉시 회수 절차 미리 준비
- **ClawHub 스킬 리뷰 강제**: 자동 설치 금지. 2026-01 이후 230+ 악성 스킬 사례 (인기 1위 스킬도 데이터 외부 유출 적발). [docs/07 §4](docs/07-openclaw-hardening.md#4-스킬-clawhub-안전-정책) 의 5단계 체크리스트
- **채널 페어링 + allowFrom**: `channels.*.dmPolicy: "pairing"` + 본인 user id 만 화이트리스트. 첫 7일 그림자 가동
- **외부 정찰 도구 사용 고려**: Cisco *DefenseClaw* (오픈소스) 를 reverse proxy 앞단에 두는 것 적극 검토

### 일반 Pi 운영 위생

- **OAuth 토큰 보호**: `~/.claude/` · `~/.openclaw/` 권한 `700`, 백업 시 암호화. 토큰은 절대 깃에 커밋 금지
- **SSH 하드닝**: 비밀번호 인증 비활성화, 키 인증 전용, `fail2ban`/`sshguard` 적용, 기본 22 포트 변경 권장
- **사용자 분리**: 에이전트 전용 유저로 실행 (root 금지). `sudo` 는 최소화
- **방화벽**: `ufw` 로 필요한 포트만 개방. OAuth 콜백 등은 일회성으로만 열고 닫기
- **로그 백업**: 외부 저장소(별도 NAS/오브젝트 스토리지)로 정기 백업
- **이용약관 준수**: BYOK 자격증명 공유 금지, **개인 사용 범위** 내에서 운용. 자동화 워크로드가 각 모델 제공자의 정책에 부합하는지 사전 확인

---

## 비용 · 전력 가늠

OpenClaw 는 **BYOK 다중 모델 라우팅** 이라 비용 구조가 두 갈래로 나뉩니다.

| 항목 | 추정값 | 적용처 |
|---|---|---|
| **OpenClaw 의 모델 호출** (Anthropic API 등) | 토큰 사용량 비례 (Sonnet ≈ $3/M input · $15/M output) | OpenClaw 의 자율 에이전트 / 스킬 호출 |
| Claude Pro 구독 | $20/월 | (선택) Claude Code CLI 의 OAuth — 사람이 직접 vibe-coding |
| Claude Max 구독 | $100 ~ $200/월 | 마찬가지 — Claude Code CLI 만 사용 |
| Pi 5 (8GB) 평균 소비 전력 | 5–8W (부하 시 ~10W) | — |
| 월 전기 요금 (한국 가정용, 24/7) | ≈ 1,000–2,000 원 | — |

> **중요**: Claude Pro/Max 구독은 OpenClaw 의 자율 호출을 *대체하지 않습니다*. OpenClaw 가 모델을 부를 때마다 BYOK API key 의 사용량으로 과금됩니다. 가벼운 개인 사용 (하루 수십 회 호출) 이면 월 $5–20 수준, 자율 코딩 루프 같은 헤비 워크로드는 월 $50+ 도 가능. [recipes/auto-coding-loop](recipes/auto-coding-loop.md) 의 cron 빈도와 변경 라인 가드로 비용 제어. 다중 에이전트로 한도를 초과하면 BYOK provider 가 스로틀링.

---

## 알려진 제약

- **공개 CVE / 보안 이슈**: CVE-2026-25253 (CVSS 8.8) / reverse-proxy 인증 우회 (93.4% 영향) / 평문 자격증명 / Prompt Injection 구조적 한계 / ClawHub 악성 스킬 230+. 운영 전 [`docs/07-openclaw-hardening.md`](docs/07-openclaw-hardening.md) 통독 필수
- **헤드리스 OAuth (Claude Code 측)**: 최초 인증 시 브라우저 콜백 필요 → SSH 포트포워딩으로 우회 ([스크립트](scripts/oauth-tunnel.sh))
- **ARM64 빌드 호환성**: 일부 Node 패키지 prebuilt 휠 부재 → 소스 빌드
- **메모리 압박**: Pi 4 4GB 에서 다중 에이전트 시 OOM — zram 또는 NVMe 스왑 권장
- **OAuth 토큰 만료**: 장기 운영 시 갱신 메커니즘 필요 (현재 수동, 자동화 검토 중)
- **레이트 리밋**: BYOK 모델 제공자의 사용량 한도 안에서만 동작 — 다중 에이전트 시 큐 스로틀링 필요
- **거버넌스 변화**: Steinberger 2026-02-14 OpenAI 합류, OpenClaw 는 foundation 으로 이전 — 향후 인터페이스 변경 가능성

---

## FAQ

**Q. Claude 구독만 있으면 OpenClaw 가 돌아가나요?**
A. **아니요.** OpenClaw 는 BYOK 라 자체적으로 API key (예: Anthropic console 의 API key) 를 받아 호출합니다. Claude Pro/Max 구독은 OpenClaw 의 호출과는 *별개 경로* 인 Claude Code CLI (사람이 직접 vibe-coding) 용으로만 의미가 있습니다. 본 Pi 에 두 도구가 공존하지만 인증·과금 경로가 다릅니다 — [`docs/04-integration.md §3`](docs/04-integration.md#3-claude-code-cli-가-같이-있는-의미) 참고.

**Q. 그럼 OpenClaw 비용은 얼마나 나오나요?**
A. BYOK provider 의 토큰 가격 × 호출량. 본 가이드 권장 `anthropic/claude-sonnet-4-6` 기준 가벼운 개인 사용은 월 $5–20, 자율 코딩 루프는 월 $50+ 수준. [비용 · 전력 가늠](#비용--전력-가늠) 표 + recipes 의 cron 빈도·변경 라인 가드로 제어.

**Q. macOS / Windows / 일반 리눅스 서버에서도 되나요?**
A. 됩니다. 본 가이드는 **ARM64 + 헤드리스** 라는 가장 까다로운 조합을 전제로 합니다. 다른 환경에서는 SSH 트릭 등이 단순화됩니다.

**Q. Pi Zero 2W / Pi 3 로도 되나요?**
A. 비권장. Node 22+ 런타임 · 메모리 · 발열 측면에서 안정 구동이 어렵습니다.

**Q. 외부에서 Pi 에이전트를 조작할 수 있나요?**
A. 가능합니다. 가장 자연스러운 경로는 OpenClaw 의 Telegram 봇에 메시지 → 자동 응답. [`recipes/remote-vibe-coding.md`](recipes/remote-vibe-coding.md) 참고.

**Q. OpenClaw 가 자가 스킬 생성을 한다는데, 안전한가요?**
A. 그것이 가장 큰 셀링 포인트이자 가장 큰 위험입니다. ClawHub 에 2026-01 이후 230+ 악성 스킬이 올라왔고, 인기 1위 스킬에서도 데이터 외부 유출이 적발됐습니다. **자동 설치 금지** + 모든 외부 스킬은 사람 리뷰 후에만 — [`docs/07 §4`](docs/07-openclaw-hardening.md#4-스킬-clawhub-안전-정책).

**Q. BYOK API key 가 만료/한도 초과되면?**
A. OpenClaw 응답이 401/429 로 실패. healthcheck.sh 가 BYOK key 자체의 만료까지는 못 보지만 gateway 응답 / 모델 호출 실패는 감지. 정기적으로 console.anthropic.com 에서 사용량 확인.

**Q. Claude Code CLI 의 OAuth 토큰이 만료되면?**
A. (vibe-coding 만 영향) 수동 재인증 필요. 자동 갱신은 로드맵.

---

## 로드맵

**라운드 1 (2026-05-16, 잘못된 청사진)** — OpenClaw 를 Python/pip 기반 작업 큐 프레임워크로 가정. 실제는 TS/Node 메시징 게이트웨이로 판명. 1차 라운드 산출물 대부분 stale.

**라운드 2 (2026-05-16~17 재작성)** — 공식 [openclaw/openclaw](https://github.com/openclaw/openclaw) 기준으로 전 산출물 재작성:

- [x] install-openclaw.sh npm 기반 재작성 (Node 22+ 검증, 최소 버전 핀 2026.2.6)
- [x] bootstrap-pi.sh Node 20 → 22
- [x] configs/openclaw.example.json5 — 실제 설정 포맷 (JSON5)
- [x] docs/03-openclaw-install.md — `openclaw onboard` 흐름
- [x] docs/04-integration.md — BYOK 라우팅 + Claude Code CLI 와의 관계
- [x] docs/00-quickstart.md Phase 3 — onboard → gateway → pair → hello
- [x] docs/05-headless-ops.md — user 모드 권장 + 시스템 모드 절차 npm 기반
- [x] docs/07-openclaw-hardening.md — CVE 인벤토리 + gateway 보안 + 스킬 리뷰
- [x] docs/troubleshooting.md C4–C6, E1-OC/CC, E2-OC/CC, E4 — OpenClaw vs Claude Code 두 경로 분리
- [x] README — 아키텍처 그림 / 보안 / 비용 (BYOK 명시) / FAQ / 알려진 제약
- [x] examples/{hello-agent, github-pr-bot, log-triage} — SKILL.md 기반 재작성
- [x] recipes 5개 — `cron.jobs` + `agents.list` + `openclaw agent --skill` 실제 인터페이스
- [x] scripts/healthcheck.sh — OpenClaw 설정 / gateway 응답 / user·system 모드 양쪽 점검
- [x] spec 에 1차 폐기 / 2차 산출물 / 교훈 기록

**검증 / 후속**:

- [ ] Pi 5 (8GB) 실 환경에서 부트스트랩 → install-openclaw → onboard → hello-agent 끝-끝 검증
- [ ] github-pr-bot `PR_BOT_DRY_RUN=1` 1주 production-shadow → 활성화
- [ ] log-triage `LOG_TRIAGE_PUBLISH=stdout` 1주 그림자 → 마스킹 보강 후 실 채널
- [ ] DefenseClaw 등 외부 보안 도구 연계 가이드
- [ ] Pi 5 NPU HAT 활용 검토 (로컬 모델 fallback)
- [ ] 한글 / 영문 문서 페어 정리

---

## 기여

이슈 · PR 환영. 보고 시 다음 명시:

- Pi 모델 (4 / 5, RAM)
- OS / 커널 버전 (`uname -a`)
- Claude Code / OpenClaw 버전
- 재현 명령 및 로그

레시피 제안은 [`recipe-request` 이슈 템플릿](.github/ISSUE_TEMPLATE/recipe-request.yml) 사용.

---

## 라이선스

MIT — [`LICENSE`](LICENSE) 참조.

---

## 관련 프로젝트

- [YawnsDuzin/claude-code-optimization](https://github.com/YawnsDuzin/claude-code-optimization) — Claude Code 최적화 노하우 모음

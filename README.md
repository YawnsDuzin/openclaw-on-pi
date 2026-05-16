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
- **Claude 구독(OAuth)** 그대로 활용 — API 별도 과금 X
- 엣지에서 GitHub PR 자동화, 로그 트리아지, IoT 모니터링 등 백그라운드 작업
- **데이터 주권**: 작업 큐·로그·자격증명·산출물을 클라우드 아닌 개인 디바이스에 보관

## OpenClaw 가 뭔가요?

`OpenClaw` 는 **작업 큐(task queue)** 를 돌면서 정의된 태스크를 단계적으로 수행하는 **자율 에이전트 프레임워크** 입니다.
본 가이드에서는 OpenClaw 가 작업을 오케스트레이션하고, **코드 작성/수정 단계만 Claude Code 에 위임** 하도록 두 도구를 엮습니다.

> 📌 OpenClaw 의 설치·구성 자체는 [`docs/03-openclaw-install.md`](docs/03-openclaw-install.md) 에서 다룹니다. (작성 예정)

## 처음 사용자라면

> 👉 **[`docs/00-quickstart.md`](docs/00-quickstart.md)** 한 페이지를 위에서 아래로 따라가세요. 빈 Pi → 24/7 가동까지 약 1시간, 단계마다 검증 명령과 실패 시 점프 위치가 명시되어 있습니다.

## TL;DR (요약 — 자세한 절차는 quickstart 참고)

```bash
# 1) 부트스트랩
git clone https://github.com/YawnsDuzin/openclaw-on-pi.git
cd openclaw-on-pi
bash scripts/bootstrap-pi.sh

# 2) Claude Code 설치 + OAuth 인증
bash scripts/install-claude-code.sh
bash scripts/oauth-tunnel.sh   # 안내문 + SSH -L 가이드
claude login

# 3) OpenClaw 설치 + 첫 동작 검증
bash scripts/install-openclaw.sh
cp -r examples/hello-agent ~/openclaw-work/ && cd ~/openclaw-work/hello-agent
bash run.sh

# 4) 헬스체크
bash ~/openclaw-on-pi/scripts/healthcheck.sh
```

> 헤드리스 환경에서 OAuth 브라우저 콜백을 받는 방법은 [`docs/02-claude-code-oauth.md`](docs/02-claude-code-oauth.md) 참고.

---

## 사전 지식

본 가이드는 다음을 전제로 합니다.

- Linux 셸 기본 (`ssh`, `systemd`, `cron`, `tmux`)
- Raspberry Pi OS 또는 Ubuntu Server 설치·플래싱 경험
- **Claude Pro 또는 Max 구독** (Free 플랜은 사용량/도구 호출 한도가 낮아 부적합)
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
│   ├── 01-prerequisites.md           # Pi 하드웨어, OS, 네트워크, 패키지
│   ├── 02-claude-code-oauth.md       # 헤드리스에서 OAuth 인증 (포트포워딩/SSH 트릭)
│   ├── 03-openclaw-install.md        # OpenClaw 설치·설정·첫 실행
│   ├── 04-integration.md             # OpenClaw ↔ Claude Code 연동
│   ├── 05-headless-ops.md            # tmux, systemd, 원격 운용, 로그 수집
│   ├── 06-performance-tuning.md      # ARM64, 스왑, NVMe, 쿨링
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
│   ├── openclaw.example.yaml
│   ├── claude-code-settings.example.json
│   ├── CLAUDE.example.md             # OpenClaw 가 참조할 컨텍스트 템플릿
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

> 🚫 **Pi Zero 2W / Pi 3 비권장**: ARM64 빌드 호환성, RAM, 발열 한계로 Claude Code + Node 런타임 + 에이전트 큐를 안정적으로 운용하기 어렵습니다.

---

## 핵심 컨셉

```
┌─────────────────────────────────────────────┐
│           Raspberry Pi (24/7)               │
│                                             │
│  ┌────────────┐        ┌──────────────┐     │
│  │  OpenClaw  │◄──────►│ Claude Code  │     │
│  │  (agent)   │        │   (OAuth)    │     │
│  └─────┬──────┘        └──────┬───────┘     │
│        │                      │             │
│        ▼                      ▼             │
│   tasks / queue       ~/.claude (creds)     │
│                                             │
└────────┬──────────────────────┬─────────────┘
         ▼                      ▼
     Git / GH API         Anthropic (OAuth)
```

OpenClaw 가 작업 큐를 돌리며, 실제 코드 작성·수정 단계에서 Claude Code 를 호출. 인증은 한 번만, 토큰은 `~/.claude` 에 저장.

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
| ⚠ | [hello-agent](examples/hello-agent/) — 끝-끝 최소 동작 (tasks.yaml + CLAUDE.md + run.sh) |
| ⚠ | [github-pr-bot](examples/github-pr-bot/) — 이슈 → PR 자동화 (pick/post + 권한 화이트리스트) |
| ⚠ | [log-triage](examples/log-triage/) — journald 로그 LLM 트리아지 (마스킹 + 채널 라우팅 + 패턴 캐시) |

> 예제 모두 best-effort 작성 완료. 실 Pi 검증 후 ✅ 로 승격.
> github-pr-bot / log-triage 는 첫 가동 시 반드시 dry-run / `LOG_TRIAGE_PUBLISH=stdout` 으로 1주일 그림자 가동.

---

## 보안 · 운영 주의사항

24/7 가동되는 Pi 는 곧 **상시 인터넷 노출 자산** 입니다. 다음을 권장합니다.

- **OAuth 토큰 보호**: `~/.claude/` 권한 `700`, 백업 시 암호화. 토큰은 절대 깃에 커밋 금지
- **SSH 하드닝**: 비밀번호 인증 비활성화, 키 인증 전용, `fail2ban`/`sshguard` 적용, 기본 22 포트 변경 권장
- **사용자 분리**: 에이전트 전용 유저로 실행 (root 금지). `sudo` 는 최소화
- **방화벽**: `ufw` 로 필요한 포트만 개방. OAuth 콜백 등은 일회성으로만 열고 닫기
- **에이전트 도구 제한**: Claude Code `settings.json` 의 권한 규칙으로 셸·네트워크·파일 접근을 화이트리스트
- **로그·작업 큐 백업**: 외부 저장소(별도 NAS/오브젝트 스토리지)로 정기 백업
- **이용약관 준수**: OAuth 자격증명 공유 금지, **개인 사용 범위** 내에서 운용. 자동화 워크로드가 Anthropic 의 구독 정책에 부합하는지 사전 확인

---

## 비용 · 전력 가늠

| 항목 | 추정값 |
|---|---|
| Claude Pro 구독 | $20/월 |
| Claude Max 구독 | $100 ~ $200/월 |
| Pi 5 (8GB) 평균 소비 전력 | 5–8W (부하 시 ~10W) |
| 월 전기 요금 (한국 가정용, 24/7) | ≈ 1,000–2,000 원 |

> 동일 워크로드를 Anthropic API 로 돌릴 경우 비용은 토큰 사용량에 비례합니다. 코드 작성·수정 위주의 지속적 에이전트 워크로드는 일반적으로 **구독제가 더 저렴**합니다. 단, 다중 에이전트로 한도를 초과하면 스로틀링됩니다 ([알려진 제약](#알려진-제약) 참고).

---

## 알려진 제약

- **헤드리스 OAuth**: 최초 인증 시 브라우저 콜백 필요 → SSH 포트포워딩으로 우회 ([스크립트](scripts/oauth-tunnel.sh))
- **ARM64 빌드 호환성**: 일부 Node / Python 패키지 prebuilt 휠 부재 → 소스 빌드
- **메모리 압박**: Pi 4 4GB 에서 다중 에이전트 시 OOM — zram 또는 NVMe 스왑 권장
- **OAuth 토큰 만료**: 장기 운영 시 갱신 메커니즘 필요 (현재 수동, 자동화 검토 중)
- **레이트 리밋**: 구독 플랜의 사용량 한도 안에서만 동작 — 다중 에이전트 시 큐 스로틀링 필요

---

## FAQ

**Q. API 키로 쓰는 거랑 뭐가 다른가요?**
A. 본 가이드는 **OAuth 구독 인증** 을 사용합니다. Pro/Max 구독자라면 API 별도 과금 없이, 구독에 포함된 사용량 한도 안에서 에이전트를 돌릴 수 있습니다.

**Q. macOS / Windows / 일반 리눅스 서버에서도 되나요?**
A. 됩니다. 본 가이드는 **ARM64 + 헤드리스** 라는 가장 까다로운 조합을 전제로 합니다. 다른 환경에서는 [OAuth 트릭](docs/02-claude-code-oauth.md) 단계 등이 단순화됩니다.

**Q. Pi Zero 2W / Pi 3 로도 되나요?**
A. 비권장. Node 런타임·메모리·발열 측면에서 안정 구동이 어렵습니다. 단순 큐 워커로 분리해 사용하는 정도는 가능합니다.

**Q. 외부에서 Pi 에이전트를 조작할 수 있나요?**
A. 가능합니다. [`recipes/remote-vibe-coding.md`](recipes/remote-vibe-coding.md) 참고.

**Q. OAuth 토큰이 만료되면 어떻게 되나요?**
A. 현재는 수동 재인증이 필요합니다. 자동 갱신은 [로드맵](#로드맵) 에 포함되어 있습니다.

**Q. 구독 플랜 한도를 넘어가면요?**
A. Anthropic 측에서 스로틀링 됩니다. 에이전트 큐에서 백오프·스로틀링 정책을 적용하거나, 작업을 분산해야 합니다.

---

## 로드맵

- [x] 베이스 설치 스크립트 ([scripts/](scripts/))
- [x] systemd 유닛 (본체 + 워치독) ([configs/systemd/](configs/systemd/))
- [x] 핵심 문서 1차 작성 (docs/01–06 + troubleshooting)
- [x] 5종 레시피 1차 작성 ([recipes/](recipes/))
- [x] OpenClaw + Claude Code 최소 통합 예제 코드 ([hello-agent](examples/hello-agent/))
- [x] github-pr-bot 코드 ([github-pr-bot](examples/github-pr-bot/))
- [x] log-triage 코드 + 마스킹 룰셋 ([log-triage](examples/log-triage/))
- [ ] Pi 5 (8GB) 실 환경에서 부트스트랩 → OAuth → hello-agent 끝-끝 검증
- [ ] github-pr-bot 1주 production-shadow → 활성화
- [ ] log-triage 마스킹 룰셋 실 로그로 보강 + 프롬프트 튜닝
- [ ] OAuth 토큰 자동 갱신 RFC
- [ ] 멀티 에이전트 큐 매니저
- [ ] Pi 5 NPU HAT 활용 검토
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

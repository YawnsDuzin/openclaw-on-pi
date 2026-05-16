# openclaw-on-pi

> 라즈베리파이에서 **OpenClaw 자율 에이전트**를 **Claude Code (OAuth 구독)** 로 24/7 구동하는 실전 가이드.
> API 키 없이 Pro/Max 구독만으로 엣지 디바이스에서 에이전트를 돌린다.

![Raspberry Pi](https://img.shields.io/badge/Raspberry%20Pi-4%2F5-c51a4a)
![Claude Code](https://img.shields.io/badge/Claude%20Code-OAuth-d97706)
![OpenClaw](https://img.shields.io/badge/OpenClaw-autonomous--agent-6366f1)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## 왜 이걸 만드는가

- 데스크탑/노트북 켜둘 필요 없이 **Pi 한 대로 자율 에이전트 상시 가동**
- **Claude 구독(OAuth)** 그대로 활용 — API 별도 과금 X
- 엣지에서 GitHub PR 자동화, 로그 트리아지, IoT 모니터링 등 백그라운드 작업

## TL;DR

```bash
git clone https://github.com/YawnsDuzin/openclaw-on-pi.git
cd openclaw-on-pi
bash scripts/bootstrap-pi.sh
```

이후 [`docs/02-claude-code-oauth.md`](docs/02-claude-code-oauth.md) 따라 OAuth 1회 인증.

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
| 쿨링 | 액티브 쿨러 필수 (Pi 5 기준) | - |
| 네트워크 | 유선 이더넷 | 안정 Wi-Fi |
| 전원 | 공식 27W USB-C PD | 5V/3A 이상 |

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

| # | 문서 | 내용 |
|---|---|---|
| 01 | [Prerequisites](docs/01-prerequisites.md) | HW · OS · 패키지 |
| 02 | [Claude Code OAuth](docs/02-claude-code-oauth.md) | 헤드리스 OAuth 인증 트릭 |
| 03 | [OpenClaw Install](docs/03-openclaw-install.md) | 설치 · 설정 · 첫 실행 |
| 04 | [Integration](docs/04-integration.md) | 두 도구 엮기 |
| 05 | [Headless Ops](docs/05-headless-ops.md) | tmux · systemd · 원격 |
| 06 | [Performance](docs/06-performance-tuning.md) | ARM64 · 스왑 · NVMe |
| ⚠ | [Troubleshooting](docs/troubleshooting.md) | 자주 깨지는 지점들 |

---

## 레시피

- [자율 코딩 루프 24/7](recipes/auto-coding-loop.md)
- [외부에서 Pi 에이전트 조작 (Remote vibe-coding)](recipes/remote-vibe-coding.md)
- [cron 기반 스케줄 작업](recipes/scheduled-agent-tasks.md)
- [멀티 에이전트 오케스트레이션](recipes/multi-agent-orchestration.md)
- [IoT 브릿지 — GPIO / MQTT 다루기](recipes/iot-bridge.md)

---

## 알려진 제약

- **헤드리스 OAuth**: 최초 인증 시 브라우저 콜백 필요 → SSH 포트포워딩으로 우회 ([스크립트](scripts/oauth-tunnel.sh))
- **ARM64 빌드 호환성**: 일부 Node / Python 패키지 prebuilt 휠 부재 → 소스 빌드
- **메모리 압박**: Pi 4 4GB 에서 다중 에이전트 시 OOM — zram 또는 NVMe 스왑 권장
- **OAuth 토큰 만료**: 장기 운영 시 갱신 메커니즘 필요 (현재 수동, 자동화 검토 중)
- **레이트 리밋**: 구독 플랜의 사용량 한도 안에서만 동작 — 다중 에이전트 시 큐 스로틀링 필요

---

## 로드맵

- [x] 베이스 설치 스크립트
- [ ] OpenClaw + Claude Code 최소 통합 예제
- [ ] systemd 워치독
- [ ] OAuth 토큰 자동 갱신
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

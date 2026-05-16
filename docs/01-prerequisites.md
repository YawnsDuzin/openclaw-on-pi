# 01 — Prerequisites

> 라즈베리파이에서 **OpenClaw** 를 24/7 안전하게 돌리기 위한 하드웨어 · OS · 패키지 · 네트워크 사전 조건. (Claude Code CLI 는 선택 — Phase 2)
>
> 처음 사용자는 [`00-quickstart.md`](./00-quickstart.md) 를 먼저 펼쳐놓고 본 문서는 Phase 1 의 참조로 사용하세요.

⚠ 검증 환경: Pi 5 (8GB) + Raspberry Pi OS 64-bit Bookworm. Pi 4 / Ubuntu Server 24.04 ARM64 는 호환 가능하지만 본 문서 작성 시점에 모든 단계가 동일 하드웨어에서 검증되지는 않았다.

---

## 1. 하드웨어

| 항목 | 권장 | 최소 | 비권장 |
|---|---|---|---|
| 보드 | Raspberry Pi 5 (8GB) | Pi 4 (4GB) | Pi Zero 2W / Pi 3 |
| 저장소 | NVMe SSD (PCIe HAT) | microSD A2 64GB+ | SD A1 / 32GB 이하 |
| 디스크 여유 | 32GB+ | 16GB | < 8GB |
| 쿨링 | 액티브 쿨러 (Pi 5 필수) | 히트싱크 + 케이스 팬 | 패시브 only |
| 네트워크 | 유선 1Gbps | 안정 Wi-Fi 5GHz | Wi-Fi 2.4GHz only |
| 전원 | 공식 27W USB-C PD | 5V/3A+ | < 3A 어댑터 |

**왜 Pi Zero 2W / Pi 3 비권장?**

- Node.js LTS 가 ARM64 only 휠을 우선 → ARMv7 빌드 호환성 문제
- 1GB RAM 으로는 Claude Code + OpenClaw 동시 구동 시 OOM
- 발열로 thermal throttling 빈발

**NVMe 권장 이유:**

- microSD 는 무작위 쓰기 IOPS 가 낮아 npm 설치, 로그 회전, OpenClaw 세션 DB (`~/.openclaw/`) 에 병목
- 24/7 운영 시 SD 마모 위험 (수개월 단위 장애 사례 다수)
- Pi 5 + PCIe HAT 조합은 약 3–4 만원 추가로 안정성을 크게 끌어올림

---

## 2. OS

다음 중 하나를 선택:

- **Raspberry Pi OS Bookworm 64-bit** ← 추천 (HW 드라이버 호환성 최상)
- **Ubuntu Server 24.04 ARM64** (LTS 5년 보장, snap 비활성 권장)

설치는 [Raspberry Pi Imager](https://www.raspberrypi.com/software/) 사용. 플래싱 단계에서 다음을 미리 설정:

- 호스트네임
- SSH 활성화 + 공개키 등록
- Wi-Fi (유선 우선 사용 시 생략)
- 사용자명 / 비밀번호 (비밀번호 인증은 추후 비활성)
- locale: `Asia/Seoul`, 키보드 `us`

---

## 3. 첫 부팅 후 점검

```bash
# 시스템 정보
uname -a
cat /etc/os-release

# 디스크 / 메모리
df -h /
free -h

# 온도 (Pi 만)
vcgencmd measure_temp 2>/dev/null || true

# 네트워크
ip -br addr
```

기대값:

- 온도 50–60℃ idle. 70℃ 넘으면 쿨링 부족.
- `/` 여유공간 16GB 이상.
- 인터넷 도달성: `curl -fsS https://anthropic.com >/dev/null && echo OK`

---

## 4. 시스템 업데이트 + 핵심 패키지

본 저장소의 부트스트랩 스크립트가 한 번에 처리:

```bash
mkdir -p /home/dzp/dzp_main/program
cd /home/dzp/dzp_main/program
git clone https://github.com/YawnsDuzin/openclaw-on-pi.git
cd /home/dzp/dzp_main/program/openclaw-on-pi
bash scripts/bootstrap-pi.sh
```

> 📁 본 가이드는 `/home/dzp/dzp_main/program/` 을 작업 베이스로 가정합니다. 다른 경로를 쓰려면 `OPENCLAW_PROGRAM_BASE=$HOME/your/path bash scripts/bootstrap-pi.sh` 처럼 환경변수로 지정.

스크립트가 설치하는 항목:

- `apt`: build-essential, ca-certificates, curl, git, gnupg, jq, python3{,-pip,-venv}, tmux, unzip, htop, rsync
- Node.js 22 (NodeSource 저장소) — OpenClaw 최소 요구 22.16, 24 권장. `NODE_MAJOR=24 bash scripts/bootstrap-pi.sh` 로 오버라이드 가능
- 운영 디렉토리: `~/.claude` (700), `/home/dzp/dzp_main/program/openclaw-work`, `~/.local/bin`

수동으로 하고 싶다면 [`scripts/bootstrap-pi.sh`](../scripts/bootstrap-pi.sh) 를 그대로 따라가면 된다.

---

## 5. 네트워크 / 방화벽 기본

24/7 노출 디바이스이므로 다음을 권장:

```bash
# UFW 설치 + 기본 정책
sudo apt-get install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH 만 허용 (필요 시 포트 변경)
sudo ufw allow 22/tcp comment 'ssh'

# 활성화
sudo ufw enable
sudo ufw status verbose
```

OAuth 콜백 시 일시적으로 사용자 단의 SSH 역포트포워딩 (`-L`) 만 사용하므로 방화벽 규칙 추가 불필요.

자세한 보안 가이드는 README 의 "보안 · 운영 주의사항" 절을 참고.

---

## 6. 사전 계정 / 자격증명

### 6-1. (필수) BYOK 모델 API key — OpenClaw 가 직접 호출

본 가이드 권장: **Anthropic API key**.

1. [console.anthropic.com](https://console.anthropic.com/) 로그인
2. **Settings → API Keys → Create Key** → 이름 (예: `openclaw-pi`) 지정
3. 발급된 `sk-ant-...` 를 즉시 안전한 곳에 복사 (한 번만 보임)
4. **Billing** 메뉴에서 결제 정보 등록 + 월 사용량 한도 설정 (월 $20-50 권장으로 시작)

OpenAI / Google / xAI 등 다른 provider 도 가능 — 각 console 에서 발급, OpenClaw 의 `agents.defaults.model.primary` 를 해당 provider 로 지정.

### 6-2. (선택) Claude Pro 또는 Max 구독 — Claude Code CLI 의 OAuth 용

- **OpenClaw 가 직접 쓰는 것이 아닙니다.** 사람이 Pi 에 SSH 들어가 `claude -p "..."` 로 vibe-coding 할 때만 의미.
- OpenClaw 만 쓸 거면 스킵.

### 6-3. (조건부) GitHub 계정 + PAT

- `examples/github-pr-bot` 같이 GitHub 자동화 스킬을 쓸 때만 필요
- fine-grained PAT 스코프: `contents:write`, `pull_requests:write`, `metadata:read`

### 6-4. (필수) 시간 동기화

```bash
timedatectl status     # NTP=active 확인
```

NTP 가 죽어 있으면 BYOK provider 의 API 호출에서 TLS 인증서 검증 / OAuth 토큰 검증이 실패합니다.

---

## 다음

- [02 — Claude Code OAuth (헤드리스 인증)](./02-claude-code-oauth.md)
- [03 — OpenClaw 설치](./03-openclaw-install.md)

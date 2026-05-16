# 01 — Prerequisites

> 라즈베리파이에서 OpenClaw + Claude Code 를 24/7 돌리기 위한 하드웨어 · OS · 패키지 · 네트워크 사전 조건.

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

- microSD 는 무작위 쓰기 IOPS 가 낮아 npm/pip 설치, 로그 회전, 큐 DB 에 병목
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
git clone https://github.com/YawnsDuzin/openclaw-on-pi.git
cd openclaw-on-pi
bash scripts/bootstrap-pi.sh
```

스크립트가 설치하는 항목:

- `apt`: build-essential, ca-certificates, curl, git, gnupg, jq, python3{,-pip,-venv}, tmux, unzip, htop, rsync
- Node.js LTS (NodeSource 저장소)
- 운영 디렉토리: `~/.claude` (700), `~/openclaw-work`, `~/.local/bin`

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

## 6. 사전 계정 / 구독

- **Claude Pro 또는 Max 구독** — Free 는 사용량/도구 호출 한도가 낮아 부적합
- **GitHub 계정 + PAT** — 에이전트가 PR 자동화를 한다면 미리 fine-grained PAT 발급
- **시간 동기화** — `timedatectl` 가 활성 상태인지 확인 (NTP 가 죽어 있으면 OAuth 토큰 검증이 실패)

---

## 다음

- [02 — Claude Code OAuth (헤드리스 인증)](./02-claude-code-oauth.md)
- [03 — OpenClaw 설치](./03-openclaw-install.md)

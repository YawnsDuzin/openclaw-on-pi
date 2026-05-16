# 06 — Performance Tuning: ARM64 · 스왑 · NVMe · 쿨링

> Pi 4/5 에서 OpenClaw + Claude Code 가 안정적으로 돌도록 OS · 저장소 · 메모리 · 쿨링을 다듬는다.

⚠ 검증 환경: Raspberry Pi 5 (8GB) + NVMe + 액티브 쿨러.

---

## 1. 우선순위

병목은 거의 항상 같은 순서다:

1. **쿨링** — throttling 한 번 들어오면 다른 모든 튜닝 의미 없음
2. **저장소** — microSD IOPS 가 npm/pip/큐 쓰기에 직격
3. **메모리 / 스왑** — 다중 워커 시 OOM
4. **CPU 거버너** — Node 빌드, 큰 컨텍스트 처리 시 throttle 회피

---

## 2. 쿨링

### 2-1. 측정

```bash
# 현재 온도
vcgencmd measure_temp

# throttle 발생 여부 (0x0 이면 깨끗)
vcgencmd get_throttled
```

`get_throttled` 비트 의미 (Pi 공식 문서):

| 비트 | 의미 |
|---|---|
| 0 | 저전압 발생 |
| 1 | ARM 주파수 capped |
| 2 | throttling 중 |
| 3 | soft temp limit |
| 16 | 부팅 후 저전압 발생 이력 |
| 17 | 부팅 후 frequency capped 이력 |
| 18 | 부팅 후 throttling 이력 |
| 19 | 부팅 후 soft temp limit 이력 |

### 2-2. 권장

- Pi 5: **공식 액티브 쿨러** 또는 동등 제품 필수
- Pi 4: 알루미늄 케이스 + 30mm 팬 (PWM)
- 케이스 안에 통기, 외부에 직사광 X
- idle 50–55℃, full load 70℃ 이내 목표

### 2-3. 거버너

기본 `ondemand` 가 일반적으로 적절. 빌드 작업이 잦다면 `performance` 로 고정:

```bash
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
# 영구 적용 (Pi)
echo "GOVERNOR=performance" | sudo tee -a /etc/default/cpufrequtils
```

→ 발열은 올라가니 쿨링 우선 점검 후 적용.

---

## 3. 저장소 — NVMe 권장

### 3-1. NVMe 부팅 (Pi 5)

PCIe HAT 장착 후:

```bash
# 부트 로더에서 NVMe 우선 순위 변경
sudo raspi-config
# → 6 Advanced Options → A4 Boot Order → B2 NVMe/USB Boot
```

기존 SD 시스템을 NVMe 로 옮기려면 [`rpi-clone`](https://github.com/billw2/rpi-clone) 사용:

```bash
sudo apt-get install -y git
git clone https://github.com/billw2/rpi-clone.git
sudo rpi-clone/rpi-clone nvme0n1
```

### 3-2. SD 만 쓰는 경우

- A2 등급, 64GB+ 권장
- `f3` 로 페이크 카드 검사:

  ```bash
  sudo apt-get install -y f3
  sudo f3probe --destructive --time-ops /dev/mmcblk0   # 데이터 날아감!
  ```

- 로그 / 큐 DB / npm 캐시는 **외장 USB SSD** 로 분리하면 마모 분산

---

## 4. 메모리 / 스왑

Pi 4 4GB 에서 멀티 큐는 거의 항상 OOM. 대책:

### 4-1. zram (RAM 압축 스왑) — 가장 빠름

```bash
sudo apt-get install -y zram-tools
echo -e "ALGO=lz4\nPERCENT=50" | sudo tee /etc/default/zramswap
sudo systemctl restart zramswap
```

확인:

```bash
swapon --show
free -h
```

### 4-2. NVMe / SSD 디스크 스왑 — 더 큰 스왑

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab
```

⚠ microSD 에 큰 스왑은 카드 마모 가속. NVMe 또는 외장 SSD 에만.

### 4-3. swappiness

```bash
echo 10 | sudo tee /proc/sys/vm/swappiness
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.d/99-openclaw.conf
```

기본 60 → 10 으로 내려서 RAM 우선 사용.

---

## 5. Node / Python ARM64 빌드

일부 npm/pip 패키지는 ARM64 prebuilt 휠이 없어 소스 빌드가 필요. 사전 패키지가 갖춰져 있으면 큰 문제 없음:

```bash
sudo apt-get install -y build-essential python3-dev libffi-dev libssl-dev cmake pkg-config
```

빌드가 너무 오래 걸리면 다음을 시도:

- npm: `--prefer-online --no-audit --fund=false` 로 캐시 무관 재시도
- pip: `--no-build-isolation` 으로 빌드 환경 재사용

---

## 6. 모델 선택

비용 / 응답속도 / 품질 trade-off. 현재 Claude 4.X 라인업 기준:

| 모델 ID | 용도 | 특징 |
|---|---|---|
| `claude-opus-4-7` | 복잡한 리팩토링, 설계 | 고품질, 느림, 토큰 비쌈 |
| `claude-sonnet-4-6` | 일상 코드 작업 | 균형. 권장 디폴트 |
| `claude-haiku-4-5-20251001` | 짧은 분류 / 트리아지 | 빠름, 저비용 |

`settings.json` 의 `"model"` 필드로 핀. 작업별로 바꾸려면 OpenClaw task 정의에서 오버라이드.

---

## 7. 네트워크

- 유선 1Gbps 권장. Wi-Fi 는 OAuth 콜백 / git push 에서 간헐적 실패의 1순위 원인
- DNS 가 느리면 호출마다 지연 누적 → `systemd-resolved` 또는 [`unbound`](https://nlnetlabs.nl/projects/unbound/) 로컬 캐시
- Anthropic 의 region 은 us — 한국에서 RTT 200ms 안팎. 응답 지연이 아니라 throughput 중요

---

## 8. 검증 — 부하 테스트

```bash
# 4시간 부하: 헬스체크 + idle 워커
for i in $(seq 1 240); do
    bash scripts/healthcheck.sh >> /tmp/hc.log 2>&1
    sleep 60
done

# 끝나고
grep FAIL /tmp/hc.log | wc -l
vcgencmd get_throttled
```

throttle 비트 16-19 가 0x0 이면 통과.

---

## 다음

- [troubleshooting](./troubleshooting.md)
- [recipes/multi-agent-orchestration](../recipes/multi-agent-orchestration.md)

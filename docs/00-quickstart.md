# 00 — Quickstart (처음 사용자 가이드)

> 이 문서 한 페이지로 **빈 Pi → OpenClaw + Claude Code 24/7 가동** 까지 끝낸다.
> 각 단계마다 검증 명령과 실패 시 점프 위치가 명시되어 있다. **위에서 아래로 순서대로** 진행하면 된다.

⚠ 검증 환경: Raspberry Pi 5 (8GB) + Raspberry Pi OS 64-bit Bookworm. Pi 4 (4GB) / Ubuntu Server 24.04 ARM64 호환은 가능하지만 일부 단계가 더 오래 걸릴 수 있다.

---

## 진행 시간 예상

| 구간 | 예상 시간 |
|---|---|
| Phase 1 (사전 점검 + 부트스트랩) | 15–25 분 |
| Phase 2 (Claude Code + OAuth) | 5–10 분 |
| Phase 3 (OpenClaw + 첫 동작 검증) | 10–15 분 |
| Phase 4 (운영 전환 — systemd) | 15–20 분 |
| **총 (운영 가동까지)** | **약 1시간** |

이후 (선택): 성능 튜닝 / 레시피 적용 / 추가 예제 활성화.

---

## 진행 흐름 한눈에

```
   ┌──────────── Phase 1 ────────────┐
   README → docs/01 → bootstrap-pi.sh
                                     │
   ┌──────────── Phase 2 ────────────┘
   install-claude-code.sh
       → docs/02 + oauth-tunnel.sh + claude login
                                     │
   ┌──────────── Phase 3 ────────────┘
   install-openclaw.sh
       → docs/03 (설정 복사)
       → examples/hello-agent (끝-끝 검증) ← 필수 체크포인트
                                     │
   ┌──────────── Phase 4 ────────────┘
   docs/04 (통합 패턴 학습)
       → docs/05 (systemd 전환) ← 운영 가동
       → healthcheck.sh

   ─────────── 이후 (선택) ───────────
   docs/06 (성능 튜닝)
   recipes/* (시나리오 적용)
   examples/{github-pr-bot, log-triage}
```

---

## Phase 1 — 사전 점검 + 부트스트랩

### 1-1. README 한 번 훑기 (5분)

`README.md` 의 **사전 지식 / 요구 사양 / 보안 · 운영 주의사항 / 알려진 제약** 섹션만 읽기.
구독은 **Claude Pro 또는 Max** 가 전제입니다 (Free 는 한도 부족).

### 1-2. HW / OS 점검 — [`docs/01-prerequisites.md`](./01-prerequisites.md)

읽고 다음을 확인:

- 보드 = Pi 5 (8GB) 권장 / Pi 4 (4GB) 최소
- 저장소 = NVMe 권장 / microSD A2 64GB+ 최소
- 쿨링 = Pi 5 는 **액티브 쿨러 필수**
- 전원 = 27W USB-C PD 권장
- OS = RPiOS 64-bit Bookworm (또는 Ubuntu Server 24.04 ARM64)

✅ 체크: 다음 명령이 모두 정상 출력

```bash
uname -a                                  # aarch64 또는 arm64
cat /etc/os-release                       # PRETTY_NAME 확인
df -h /                                   # 여유 공간 16GB 이상
free -h                                   # MemTotal 4GB 이상
vcgencmd measure_temp 2>/dev/null         # 60℃ 이하 (Pi 만)
curl -fsS https://anthropic.com >/dev/null && echo OK
```

❌ 실패 시: [`docs/01-prerequisites.md`](./01-prerequisites.md) 의 해당 항목 / [`troubleshooting.md`](./troubleshooting.md) F절 (네트워크).

### 1-3. 저장소 클론 + 부트스트랩

> 📁 **경로 규약**: 본 가이드는 `/home/dzp/dzp_main/program/` 을 작업 베이스로 사용합니다. 다른 사용자/경로를 쓰려면 모든 `/home/dzp/dzp_main/program` 을 본인 경로로 치환하거나, 스크립트에 `OPENCLAW_PROGRAM_BASE=$HOME/your/path` 환경변수를 지정하세요.

```bash
# 작업 베이스 디렉토리 생성
mkdir -p /home/dzp/dzp_main/program
cd /home/dzp/dzp_main/program

git clone https://github.com/YawnsDuzin/openclaw-on-pi.git
cd /home/dzp/dzp_main/program/openclaw-on-pi

bash scripts/bootstrap-pi.sh
```

스크립트가 하는 일: apt 업데이트, 핵심 패키지 설치, Node.js 20 LTS, `~/.claude` (700) / `/home/dzp/dzp_main/program/openclaw-work` / `~/.local/bin` 디렉토리 준비.

✅ 체크:

```bash
node --version            # v20.x
python3 --version         # 3.x
ls -ld ~/.claude          # 권한이 700
```

❌ 실패 시: [`troubleshooting.md`](./troubleshooting.md) C절 (빌드/의존성).

> ⏸ **여기서 멈춰도 됨** — 시간이 없으면 다음 세션에 Phase 2 부터 이어서.

---

## Phase 2 — Claude Code + OAuth

### 2-1. Claude Code CLI 설치

```bash
bash scripts/install-claude-code.sh

# 현재 셸에 PATH 적용 (스크립트가 ~/.bashrc 에 영구 등록은 자동 처리)
export PATH="$HOME/.npm-global/bin:$PATH"
```

✅ 체크:

```bash
claude --version          # 정상 출력
which claude              # ~/.npm-global/bin/claude (또는 PATH 의 다른 곳)
```

❌ 실패 시: [`troubleshooting.md`](./troubleshooting.md) C1 (npm EACCES) / C3 (Node 버전) / **C6 (PATH 누락 — `claude: 명령어를 찾을 수 없음`)**.

### 2-2. OAuth 1회 인증 — [`docs/02-claude-code-oauth.md`](./02-claude-code-oauth.md)

[`docs/02`](./02-claude-code-oauth.md) §1 ("본질") 만 먼저 읽고 (왜 SSH 트릭이 필요한지), 다음 절차:

1. **로컬 PC** 에서 SSH 세션을 새로 엶:

   ```bash
   ssh -L 54545:localhost:54545 <user>@<pi-host>
   ```

2. **Pi** 에서 안내 출력 (선택):

   ```bash
   bash scripts/oauth-tunnel.sh
   ```

3. **Pi** 에서 인증:

   ```bash
   claude login
   ```

   출력된 `https://...` URL 을 **로컬 PC 브라우저** 에 붙여넣기 → Anthropic 로그인 → 콜백이 SSH 터널을 타고 Pi 에 도달.

4. 권한 정리:

   ```bash
   chmod 700 ~/.claude
   chmod 600 ~/.claude/credentials.json
   ```

✅ 체크:

```bash
ls -la ~/.claude/credentials.json     # 권한 600
claude -p "say 'ok' and nothing else" # ok 한 단어
```

❌ 실패 시: [`troubleshooting.md`](./troubleshooting.md) A절 (OAuth) — A1 콜백 안 옴 / A2 redirect_uri / A3 시계 동기화.

> ✅ **첫 결제·인증의 끝.** 이 이후는 토큰 만료 전까지 재인증 불필요.

---

## Phase 3 — OpenClaw + 첫 동작 검증

### 3-1. OpenClaw 설치

```bash
bash scripts/install-openclaw.sh
```

스크립트가 자동 모드 감지 (pipx > pip > git). 모드 강제:

```bash
OPENCLAW_INSTALL_MODE=pipx bash scripts/install-openclaw.sh
```

✅ 체크:

```bash
openclaw --version
which openclaw
```

PATH 에 안 잡히면 `~/.bashrc` 에 `export PATH="$HOME/.local/bin:$PATH"` 추가 후 `source ~/.bashrc`.

❌ 실패 시: [`docs/03-openclaw-install.md`](./03-openclaw-install.md) §2 / [`troubleshooting.md`](./troubleshooting.md) C2 (ARM64 휠 빌드).

### 3-2. 설정 파일 복사 — [`docs/03-openclaw-install.md`](./03-openclaw-install.md)

```bash
mkdir -p /home/dzp/dzp_main/program/openclaw-work
cp configs/openclaw.example.yaml /home/dzp/dzp_main/program/openclaw-work/openclaw.yaml
cp configs/CLAUDE.example.md     /home/dzp/dzp_main/program/openclaw-work/CLAUDE.md
cp configs/claude-code-settings.example.json ~/.claude/settings.json
```

[`docs/03`](./03-openclaw-install.md) §3 표를 보고 **`/home/dzp/dzp_main/program/openclaw-work/openclaw.yaml`** 에서 다음 키만 자기 환경에 맞게:

- `runtime.claude_code.model` (Pi 4 라면 `claude-haiku-4-5-20251001` 권장)
- `queues[].max_concurrent` (Pi 4 4GB → `1`, Pi 5 8GB → `2`)

### 3-3. ★ 끝-끝 검증 — `examples/hello-agent`

**가장 중요한 체크포인트.** 이게 통과하면 OpenClaw ↔ Claude Code 파이프라인이 살아있다는 뜻.

```bash
cd /home/dzp/dzp_main/program/openclaw-work
cp -r /home/dzp/dzp_main/program/openclaw-on-pi/examples/hello-agent .
cd hello-agent
bash run.sh
```

✅ 체크 (모두 통과해야 OK):

```bash
git log -1 --pretty=%s | grep -q "^chore(hello): hello-agent demo run$" && echo "commit OK"
git show --stat HEAD | grep -q "README.md"                              && echo "diff OK"
grep -q "OpenClaw says hi at " README.md                                && echo "content OK"
```

3줄 모두 출력되면 ✅. **여기까지 됐으면 본 저장소의 약속이 실제로 동작한다는 증거.**

❌ 실패 시:
- `claude` 호출 자체 실패 → [`troubleshooting.md`](./troubleshooting.md) A4 / E1
- 권한 거부 → E2 (settings.json 의 allow 보강)
- 무한 재시도 → E3 (재시도 정책)

> ⏸ **여기서 멈춰도 됨** — 운영 전환은 Phase 4. 지금까지가 "맛보기" 라면 충분.

---

## Phase 4 — 운영 전환 (systemd 24/7)

### 4-1. 통합 패턴 한 번 읽기 — [`docs/04-integration.md`](./04-integration.md)

15분 분량. **꼭 읽어야 하는 절**:

- §2-1 단발 위임 패턴 — `claude -p --add-dir ... --output-format json`
- §3 CLAUDE.md 활용
- §4 권한 화이트리스트 (settings.json `permissions.deny` 우선 원칙)

### 4-2. systemd 전환 — [`docs/05-headless-ops.md`](./05-headless-ops.md)

`docs/05` §2 절을 그대로 따라가면 됩니다 — 전용 사용자 생성 / 디렉토리 권한 / 유닛 설치 / timer 활성화. 핵심 명령만:

```bash
# 사용자 + 디렉토리 (자세한 옵션은 docs/05 §2-1)
sudo useradd -r -m -d /opt/openclaw -s /usr/sbin/nologin openclaw
sudo mkdir -p /opt/openclaw/scripts /etc/openclaw /var/lib/openclaw /var/log/openclaw
sudo chown -R openclaw:openclaw /opt/openclaw /var/lib/openclaw /var/log/openclaw

# 유닛 설치
sudo cp configs/systemd/openclaw.service          /etc/systemd/system/
sudo cp configs/systemd/openclaw-watchdog.service /etc/systemd/system/
# (timer 정의는 docs/05 §2-2 참고)

sudo systemd-analyze verify /etc/systemd/system/openclaw*.service
sudo systemctl daemon-reload
sudo systemctl enable --now openclaw.service openclaw-watchdog.timer
```

✅ 체크:

```bash
systemctl is-active openclaw.service           # active
journalctl -u openclaw.service -n 20 --no-pager
bash scripts/healthcheck.sh && echo "HC OK"    # 종료 코드 0 또는 2(warn-only)
```

❌ 실패 시: [`troubleshooting.md`](./troubleshooting.md) B절 (systemd) — B1 재시작 루프 / B2 권한.

### 4-3. 보안 마무리

[`README.md` 의 "보안 · 운영 주의사항"](../README.md#보안--운영-주의사항) 의 체크박스 5개 — SSH 하드닝 / 방화벽 / 사용자 분리 / 토큰 보호 / 백업.
세부 절차는 [`docs/05-headless-ops.md`](./05-headless-ops.md) §4 ("원격 접근").

> ✅ **여기까지 = 운영 가동 완료.** 24/7 백그라운드에서 OpenClaw 가 큐를 돌립니다.

---

## 이후 (선택)

| 목적 | 가는 곳 |
|---|---|
| 성능 / 발열 / 메모리 압박 잡기 | [`docs/06-performance-tuning.md`](./06-performance-tuning.md) |
| 자율 코딩 루프 24/7 활성화 | [`recipes/auto-coding-loop.md`](../recipes/auto-coding-loop.md) |
| 외부에서 Pi 조작 (모바일) | [`recipes/remote-vibe-coding.md`](../recipes/remote-vibe-coding.md) |
| cron / systemd timer 정기 작업 | [`recipes/scheduled-agent-tasks.md`](../recipes/scheduled-agent-tasks.md) |
| 역할별 봇 분리 (트리아지/코더/리포터) | [`recipes/multi-agent-orchestration.md`](../recipes/multi-agent-orchestration.md) |
| GPIO / MQTT 센서 통합 | [`recipes/iot-bridge.md`](../recipes/iot-bridge.md) |
| GitHub 이슈 → PR 자동화 (예제) | [`examples/github-pr-bot/`](../examples/github-pr-bot/) — **첫 가동 시 `PR_BOT_DRY_RUN=1` 1주일 그림자** |
| journald 로그 트리아지 (예제) | [`examples/log-triage/`](../examples/log-triage/) — **첫 가동 시 `LOG_TRIAGE_PUBLISH=stdout` 1주일** |

---

## 막혔을 때

| 증상 카테고리 | 점프 |
|---|---|
| OAuth / 인증 / 토큰 | [`troubleshooting.md`](./troubleshooting.md) **A절** |
| systemd 유닛 / 워치독 | **B절** |
| npm / pip / Node 빌드 | **C절** |
| OOM / throttle / 디스크 | **D절** |
| `claude` 호출 / 큐 / 권한 거부 | **E절** |
| 네트워크 / DNS / SSL | **F절** |
| 보안 (fail2ban / credentials 누출) | **G절** |

위 표에 없는 케이스는 [bug 이슈 템플릿](../.github/ISSUE_TEMPLATE/bug.yml) 으로 신고.

---

## 진척 체크리스트

Phase 별로 끝났는지 빠르게 확인:

- [ ] **P1** `bash scripts/bootstrap-pi.sh` 통과 + `node --version` 정상
- [ ] **P2** `claude -p "say ok"` → `ok` 출력
- [ ] **P3** `examples/hello-agent` 검증 3줄 모두 출력
- [ ] **P4** `systemctl is-active openclaw.service` = `active` + `healthcheck.sh` 종료 코드 0/2

4개 모두 ✅ 면 본 저장소의 약속이 당신의 Pi 에서 살아있는 상태입니다.

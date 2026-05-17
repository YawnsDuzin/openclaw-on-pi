# Recipe — 외부에서 Pi 에이전트 원격 조작

> 외출/이동 중에 휴대폰 또는 노트북에서 Pi 의 OpenClaw 에 작업을 던지고 결과를 확인한다.

⚠ 검증 환경: OpenClaw ≥ 2026.2.6 + Telegram (또는 다른 메시징 채널) + 선택적으로 Tailscale 메시 VPN.

> 📜 OpenClaw 는 본질적으로 메시징 게이트웨이라 **모바일 채팅 앱 = 자연스러운 원격 에이전트 UI**. SSH 는 비상용.

---

## 시나리오

- 통근 중 떠오른 작업: "이 README 의 영어 번역 초안 만들어둬"
- 카페에서 노트북: 본격 작업 전에 빌드/테스트 큐를 미리 메시지로 던져둠
- 응답을 기다리지 않고 메시지만 보냄 → 도착해서 결과 리뷰

OpenClaw 의 메인 UI 가 메시징이라 **별도 도구 없이 휴대폰 Telegram 만 있으면 끝**. SSH/Tailscale 은 채널이 깨졌을 때의 백업 경로.

---

## 옵션 A — Telegram 봇 (권장 / 1순위)

[03 — OpenClaw 설치 §5](../docs/03-openclaw-install.md#5-메시징-채널-연결--telegram-예시) 에서 이미 설정한 Telegram 봇을 그대로 사용. 외부 어디서든 본인 휴대폰의 Telegram 앱으로:

```
나: README.en.md 초안을 영어로 번역해서 PR 만들어줘
봇: 작업 시작했어요. /cleanup-issue 스킬은 아니고 ad-hoc agent 호출입니다.
    예상 5분 — 끝나면 다시 알릴게요.
나: /status
봇: 진행 중 (3분 경과). 마지막 도구: gh repo view.
나: (5분 후)
봇: PR 생성 완료: https://github.com/youruser/yourrepo/pull/42
    변경 라인: 18. 본문 미리보기:
    > "README 영문 초안. 자세한 리뷰 후 머지 부탁..."
```

### 안전 베이스라인 (필수)

`~/.openclaw/openclaw.json`:

```json5
{
  channels: {
    telegram: {
      enabled: true,
      botToken: "REPLACE_VIA_ENV:TELEGRAM_BOT_TOKEN",
      dmPolicy: "pairing",                  // 페어링 안 된 사용자 차단
      allowFrom: ["tg:000000000"],          // 본인 user id 만
      rateLimit: { perUser: 30 },           // 분당 30메시지 한도
    },
  },
}
```

> 🚨 `allowFrom` 빈 배열 + `dmPolicy: "open"` 으로 바꾸지 말 것 — 누구나 봇에 명령 보낼 수 있는 상태가 됨. [docs/07 §1](../docs/07-openclaw-hardening.md#1-알려진-cve--취약점-인벤토리) 의 reverse-proxy 우회 사례와 본질이 같음.

---

## 옵션 B — Tailscale SSH (백업)

채널이 안 잡힐 때 (Telegram 차단 지역, 봇 토큰 회수 직후 등) 의 비상 경로.

### 1) Tailscale 설치 (Pi)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh --accept-routes
tailscale status
```

`--ssh` 가 Tailscale 자체 SSH 채널을 열어 SSH 키 관리까지 통합.

### 2) 모바일 / 노트북 클라이언트

각 플랫폼 Tailscale 앱 설치 → 같은 계정 로그인. Pi 가 `pi-bookworm.tail-xxxx.ts.net` 호스트네임으로 잡힘.

### 3) SSH 로 직접 명령

```bash
ssh dzp@pi-bookworm.tail-xxxx.ts.net
openclaw agent --message "README 영문 초안 작성해서 PR 만들어"
openclaw status
```

세션이 오래 살아있어야 하므로 Termux/iSH 에서는 `tmux` 또는 `mosh` 권장:

```bash
sudo apt-get install -y mosh
sudo ufw allow 60000:60100/udp comment 'mosh'
```

---

## 옵션 C — 다른 채널 (Slack / Discord / Signal / iMessage)

OpenClaw 는 22+ 채널 지원. 각자 페어링 절차 + dmPolicy 가 다르므로 [공식 docs](https://docs.openclaw.ai/) 의 channel-specific 가이드 확인. 본 가이드의 권장 1순위는 Telegram (가장 단순한 봇 페어링 + dmPolicy pairing 강제).

---

## 운영 팁

- **알림 도착 보장**: Pi 가 슬립 / 네트워크 끊김으로 OpenClaw 가 죽으면 메시지가 안 옴. `healthcheck.sh` 결과를 별도 채널 (ntfy.sh) 로 1일 1회 보내는 *카나리* 패턴 추천
- **모바일에서 큰 컨텍스트 입력**: 화면이 작아 긴 prompt 작성이 불편. 자주 쓰는 작업은 **스킬로 만들어 슬래시 명령** 으로 (`/cleanup-issue` 같은)
- **Tailscale ACL**: 분실 가능한 모바일 노드는 별도 태그로 격리. 분실 시 즉시 회수
- **Telegram 그룹 채팅 금지**: 봇을 그룹에 초대하면 다른 멤버도 메시지를 보낼 수 있음. `allowFrom` 만으로는 부족 — 봇은 본인 1:1 DM 에서만

---

## 알려진 한계

- **셀룰러 RTT**: 메시지 왕복이 수초 추가됨. enqueue-and-forget 패턴 (메시지만 던지고 결과는 나중에 확인) 이 현실적
- **OAuth/BYOK 토큰 만료**: 외출 중 만료되면 봇이 모든 메시지에 401. 분기 1회 갱신 절차 미리 준비
- **Prompt Injection 위험 증가**: 외부에서 보낸 메시지를 모델이 그대로 읽으면 위험. allowFrom + dmPolicy 가 1차 방어, [docs/07 §6](../docs/07-openclaw-hardening.md#6-prompt-injection-운영-완화) 가 2차
- **봇 토큰 분실**: BotFather 에서 `/revoke` 즉시 가능. 침해 대응 절차는 [docs/07 §7](../docs/07-openclaw-hardening.md#7-사고-시-체크리스트)

---

## 다음

- [자율 코딩 루프](./auto-coding-loop.md)
- [멀티 에이전트 오케스트레이션](./multi-agent-orchestration.md)
- [07 — Hardening](../docs/07-openclaw-hardening.md)

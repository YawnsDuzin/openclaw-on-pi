# Recipe — 외부에서 Pi 에이전트 조작 (Remote Vibe-Coding)

> 외출/이동 중에 휴대폰 또는 노트북에서 Pi 의 OpenClaw 에 작업을 던지고 결과를 확인한다.

⚠ 검증 환경: Tailscale 메시 VPN + iSH (iOS) / Termux (Android) / 일반 SSH 클라이언트.

---

## 시나리오

- 통근 중 떠오른 작업: "이 README 의 영어 번역 초안 만들어둬"
- 카페에서 노트북: 본격 작업 전에 Pi 에 빌드/테스트 큐를 미리 던져둠
- 응답을 기다리지 않고 큐에 enqueue 만 → 도착해서 결과 리뷰

---

## 필요 조건

- Pi 가 24/7 가동 ([05 — Headless Ops](../docs/05-headless-ops.md))
- 외부에서 안전하게 도달할 수단 — 본 레시피는 [Tailscale](https://tailscale.com/) 사용
- 모바일 SSH 클라이언트 (Termius, Blink, Ghostty mobile 등)

---

## 단계

### 1) Tailscale 설치 (Pi)

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh --accept-routes
tailscale status
```

`--ssh` 가 Tailscale 자체 SSH 채널을 열어 SSH 키 관리까지 통합.

### 2) Tailscale 설치 (모바일 / 노트북)

각 플랫폼 앱 설치 후 같은 계정 로그인. Pi 가 `pi-bookworm.tail-xxxx.ts.net` 같은 호스트네임으로 잡힌다.

### 3) 모바일 SSH 클라이언트로 테스트

```bash
ssh <user>@pi-bookworm.tail-xxxx.ts.net
openclaw status
```

세션이 오래 살아있어야 하므로 Termux/iSH 에서는 `tmux` 또는 `mosh` 를 권장.

### 4) 작업 enqueue 단축 명령

자주 쓰는 패턴은 Pi 안에 셸 함수로:

`~/.bashrc` 에:

```bash
openclaw-q() {
    local prompt="$*"
    [[ -z "$prompt" ]] && { echo "usage: openclaw-q <prompt>"; return 1; }
    openclaw enqueue --queue default --task adhoc --payload "{\"prompt\": $(jq -Rs . <<< "$prompt")}"
}
```

모바일에서 한 줄로:

```bash
openclaw-q "README.en.md 초안을 영어로 번역해서 PR 만들어"
```

### 5) 결과 확인

```bash
openclaw queue ls --status done --limit 5
openclaw queue show <task-id>
gh pr list --author "@me" --limit 5
```

---

## 운영 팁

- **mosh 추천**: 4G/5G 셀룰러 환경에서 SSH 보다 끊김에 강함

  ```bash
  sudo apt-get install -y mosh
  sudo ufw allow 60000:60100/udp comment 'mosh'
  ```

- **Tailscale ACL** 로 디바이스별 접근 제한. 잃어버린 폰의 노드 즉시 회수
- **알림 채널**: 작업 완료를 휴대폰에서 받으려면 OpenClaw 의 `watchdog.alerts` 로 webhook → ntfy.sh / Pushover

  ```yaml
  watchdog:
    alerts:
      - type: webhook
        url: https://ntfy.sh/<your-topic>
  ```

---

## 알려진 한계

- **모바일에서 큰 컨텍스트 입력**: 화면이 작아 긴 prompt 작성이 불편. 한 줄짜리 task 위주로 설계
- **응답 시간**: 셀룰러 RTT 가 더해지면 인터랙티브 디버깅은 비현실적. enqueue-and-forget 패턴 권장
- **OAuth 만료**: 외출 중 만료되면 재인증 불가 (브라우저 + SSH `-L` 필요). [02 — OAuth](../docs/02-claude-code-oauth.md) 의 토큰 나이 모니터링이 중요

---

## 다음

- [자율 코딩 루프](./auto-coding-loop.md)
- [멀티 에이전트 오케스트레이션](./multi-agent-orchestration.md)

# 07 — OpenClaw Hardening

> 24/7 Pi 에 OpenClaw 를 띄우는 것은 **상시 인터넷 노출 자율 에이전트** 를 운영하는 것이다. 본 문서는 알려진 위험 + 운영 권장값 + 사고 대응까지.

⚠ 검증 환경: OpenClaw ≥ 2026.2.6. 본 가이드의 모든 운영 권장은 [공식 OpenClaw 문서](https://docs.openclaw.ai/) + [clawdocs.org/security](https://clawdocs.org/security/) + [Cisco AI 보안 보고서](https://blogs.cisco.com/ai/personal-ai-agents-like-openclaw-are-a-security-nightmare) 의 공개 자료를 인용한다.

---

## 1. 알려진 CVE / 취약점 인벤토리

| CVE / 케이스 | CVSS | 영향 버전 | 패치 | 핵심 |
|---|---|---|---|---|
| **CVE-2026-25253** | **8.8 Critical** | < 2026.1.29 | 2026.1.29 (2026-01-30) | Gateway Control UI 가 `gatewayUrl` 무검증 → WebSocket 으로 **인증 토큰 외부 전송**. |
| **CVE-2026-25157** | High | macOS 앱 | (개별 패치) | SSH 처리에서 OS command injection — 로컬/원격 임의 명령 실행. Pi(Linux) 는 직접 영향 없으나 macOS 페어링 클라이언트 사용 시 주의. |
| **Gateway 인증 우회 (Reverse Proxy)** | — | 모든 버전, 미설정 시 | 설정으로 보강 | Nginx/Caddy/Traefik 등 뒤 배포 시 모든 외부 요청이 `127.0.0.1` 로 보여 **인증 우회**. 공개 노출 인스턴스의 **약 93.4%** 가 영향. |
| **자격증명 평문 저장** | — | 모든 버전 | (구조적, 완화만 가능) | API 키 · 게이트웨이 토큰이 `~/.openclaw/` 하위에 평문. 머신 침해 시 모든 연결 계정 노출. 백업에도 잔존. |
| **ClawHub 악성 스킬 230+** | — | — | VirusTotal 스캐너 (≥ 2026.2.6) | 2026-01-27 이후 230 개 이상의 악성 스킬이 ClawHub 에 업로드. 1위 인기 스킬 "What Would Elon Do?" 가 데이터 외부 유출 + 프롬프트 인젝션 적발. |
| **Prompt Injection (구조적)** | — | 모든 버전 | 디자인 결함 — 운영 완화만 가능 | 메시지/이메일/웹 본문에 숨긴 지시문이 LLM 을 조작 → 데이터 유출 / 명령 실행 / 자기 설정 변경. |

> **최소 버전 핀**: 본 가이드의 모든 절차는 **OpenClaw ≥ 2026.2.6** 가정. `scripts/install-openclaw.sh` 가 이 미만이면 경고를 띄운다. `openclaw --version` 으로 늘 확인.

---

## 2. Gateway 보안 베이스라인

본 저장소의 `configs/openclaw.example.json5` 가 채택한 기본값. **이 4가지가 깨지면 외부 노출은 절대 금지**.

```json5
{
  gateway: {
    host: "127.0.0.1",          // ✅ loopback 만
    bind: "loopback",           // ✅ 명시적 loopback
    auth: {
      mode: "token",
      token: "REPLACE_VIA_ENV:OPENCLAW_GATEWAY_TOKEN",   // ✅ env 주입
      rateLimit: { maxAttempts: 10, windowMs: 60000, exemptLoopback: true },
    },
    trustedProxies: [],         // ✅ 외부 노출 안 할 거면 빈 배열
  },
}
```

env 주입은 systemd 유닛 또는 `~/.bashrc` 가 아니라 **별도 권한 600 파일**:

```bash
mkdir -p ~/.openclaw-secrets && chmod 700 ~/.openclaw-secrets
cat > ~/.openclaw-secrets/env <<'EOF'
OPENCLAW_GATEWAY_TOKEN=$(openssl rand -hex 32)
OPENCLAW_HOOKS_TOKEN=$(openssl rand -hex 32)
EOF
chmod 600 ~/.openclaw-secrets/env
# systemd 유닛에서: EnvironmentFile=-/home/dzp/.openclaw-secrets/env
```

---

## 3. 외부 노출이 필요한 경우 — reverse proxy 안전 절차

본 가이드의 **권장 = 외부 노출 안 함**. 외부에서 Pi 에 접근하려면 [`recipes/remote-vibe-coding.md`](../recipes/remote-vibe-coding.md) 의 **Tailscale / WireGuard / SSH 터널** 방식을 사용. 그래도 reverse proxy 가 필요하면:

### 3-1. trustedProxies 명시

```json5
{
  gateway: {
    host: "127.0.0.1",
    bind: "loopback",
    trustedProxies: ["10.0.0.5"],   // proxy 의 *고정* 사설 IP
    auth: {
      // identity-aware proxy 가 인증을 책임지면 trusted-proxy 모드로
      mode: "trusted-proxy",
      trustedProxy: { userHeader: "x-forwarded-user" },
    },
  },
}
```

### 3-2. proxy 자체 보안

- Caddy/Nginx 에서 **mTLS** 또는 OIDC/Cloudflare Access 강제
- 외부 → proxy → OpenClaw 경로 외 다른 inbound 차단 (ufw)
- Cisco 의 **DefenseClaw** ([blog](https://blogs.cisco.com/ai/cisco-announces-defenseclaw)) 를 reverse proxy 앞단에 두는 것을 적극 검토 — 프롬프트 인젝션 탐지 / 데이터 유출 모니터링 / 스킬 정책 적용.

### 3-3. 확인

```bash
# 외부에서 직접 18789 가 닫혀 있는지 (반드시 timeout)
nc -zv <pi-public-ip> 18789

# proxy 를 거치지 않은 직접 접속이 401/403 인지
curl -s -o /dev/null -w "%{http_code}\n" https://<pi-public-ip>/agent
```

"Have I Been Clawned?" 외부 점검 도구가 있다면 한 번 통과시켜 본다.

---

## 4. 스킬 (ClawHub) 안전 정책

ClawHub 외부 스킬은 230+ 건의 악성 사례가 있다. 본 가이드의 **운영 기본값**:

| 정책 | 설정 / 운영 |
|---|---|
| 자동 설치 금지 | `openclaw skills install` 을 **사람 리뷰 후에만** 실행. CI/cron 으로 자동 설치 금지. |
| 출처 화이트리스트 | 공식 `openclaw/*` 스킬과 신뢰 가능한 메인테이너의 스킬만 |
| VirusTotal 스캐너 활성화 | `tools.skills.virusTotalScan: true` (v2026.2.6+) |
| 코드 안전성 스캐너 | 내장 정적 분석 활성화 |
| 커뮤니티 신고 자동 hide | 3건 이상 신고된 스킬 자동 차단 |
| 사용자 리뷰 체크리스트 | 본 절 §4-1 |

### 4-1. 스킬 설치 전 리뷰 체크리스트

설치 후보 스킬의 `SKILL.md` 를 *반드시* 다음 순서로 본다:

1. **frontmatter** 의 `name:` `description:` 가 실제 동작과 일치하는지
2. **bundled `scripts/`** — 외부 도메인 호출 (`curl`, `wget`, raw IP), `eval` / `Function()`, base64 디코딩 후 실행 등 의심 패턴
3. **requires.env** / **requires.bins** — 요청하는 자격증명 / 바이너리가 description 과 맞는지 (예: 단순 README 편집 스킬이 `GITHUB_TOKEN` 을 요구한다면 의심)
4. **maintainer** — GitHub 활동 / 다른 스킬 / 신고 이력
5. **변경 이력** — 최근 push 가 정상 release 패턴인지, 갑자기 한 줄짜리 커밋이 들어왔는지

> 💡 1위 스킬도 안전하지 않다 — "What Would Elon Do?" 사례가 그 증거. **인기 ≠ 안전**.

---

## 5. 자격증명 보호 (`~/.openclaw/` 평문 저장 대응)

OpenClaw 는 구조적으로 자격증명을 평문 저장한다. 완화책:

1. **디렉토리 권한**:

   ```bash
   chmod 700 ~/.openclaw
   chmod 600 ~/.openclaw/openclaw.json
   ```

2. **백업 분리**: 일반 백업 도구 (`rsync`, `borgbackup`) 에서 `~/.openclaw/` 제외. 자격증명을 별도 암호화 백업으로.

3. **토큰 회전**: 분기 1회 `openclaw rotate` (해당 명령이 없으면 수동 — onboard 재실행 후 envFile 갱신).

4. **머신 침해 가정 대응**: Pi 가 침해됐다고 가정하고 다음을 즉시 실행할 절차를 미리 적어둘 것:
   - Anthropic / OpenAI 대시보드에서 해당 API key 즉시 회수
   - Telegram 봇 토큰 재발급 (BotFather `/revoke`)
   - GitHub PAT 재발급
   - `~/.openclaw/` 통째 삭제 후 onboard 재실행

---

## 6. Prompt Injection 운영 완화

LLM 본질의 한계라 완전 방지 불가. 다음 운영 패턴으로 *영향* 을 제한.

| 패턴 | 적용 |
|---|---|
| 메시지 출처 화이트리스트 | `channels.*.allowFrom` 으로 본인 + 신뢰 인원만 |
| 외부 본문 인용 시 격리 | 이메일/웹 본문은 별도 sandbox 도구로 요약 후 LLM 에 |
| 파괴적 액션 confirm | `git push`, `rm -rf`, 결제 등은 사람 confirm 강제 |
| 도구별 deny 우선 | `tools.*.policy.deny` 를 먼저 명시, allow 는 화이트리스트 |
| 로그 + 알람 | `logging.level: info` + 비정상 동작 (외부 도메인 자동 호출 등) 알람 |
| 1주일 그림자 가동 | 새 스킬 / 새 채널 활성화 후 첫 7일은 응답을 dry-run / stdout 로만 |

---

## 7. 사고 시 체크리스트

수상한 동작 (외부 도메인 자동 호출, 자기 설정 변경, 응답이 갑자기 다른 사용자에게 전송) 발견 시:

```bash
# 1) Gateway 즉시 정지
systemctl --user stop openclaw           # 또는 sudo systemctl stop openclaw
pkill -f 'openclaw gateway' || true

# 2) 최근 로그 보관
journalctl --user -u openclaw --since "24 hours ago" > /tmp/openclaw-incident.log
# 또는 시스템 모드면:
sudo journalctl -u openclaw --since "24 hours ago" > /tmp/openclaw-incident.log

# 3) 토큰 즉시 회수 (위 §5-4)

# 4) 최근 설치 스킬 점검
ls -lat ~/.openclaw/skills/ | head -20
# 의심 스킬은 그 자리에서 격리 (rename + chmod 000)

# 5) 침해 가정 클린 재설치
mv ~/.openclaw{,.compromised.$(date +%s)}
bash scripts/install-openclaw.sh
openclaw onboard --install-daemon
```

신고 / 보고:

- OpenClaw 보안 채널 (GitHub security advisories) 에 보고
- 사용한 채널의 운영자 (Telegram BotFather 신고 등) 에게 통보
- Cisco DefenseClaw / 외부 모니터링을 두고 있었다면 그 로그 동봉

---

## 8. 외부 자료

- 공식: [openclaw/openclaw GitHub](https://github.com/openclaw/openclaw) · [docs.openclaw.ai](https://docs.openclaw.ai/)
- 보안: [clawdocs.org/security/known-vulnerabilities](https://clawdocs.org/security/known-vulnerabilities/)
- Cisco: [Personal AI Agents like OpenClaw Are a Security Nightmare](https://blogs.cisco.com/ai/personal-ai-agents-like-openclaw-are-a-security-nightmare) · [DefenseClaw 발표](https://blogs.cisco.com/ai/cisco-announces-defenseclaw)
- 분석: [Penligent — Prompt Injection 분석](https://www.penligent.ai/hackinglabs/the-openclaw-prompt-injection-problem-persistence-tool-hijack-and-the-security-boundary-that-doesnt-exist/)

본 문서는 위 출처들이 갱신되면 함께 업데이트되어야 한다.

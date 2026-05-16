# Recipe — 멀티 에이전트 오케스트레이션

> Pi 한 대에서 OpenClaw 의 `agents.list[]` 로 역할별 에이전트를 분리해 모델 / 스킬 화이트리스트 / BYOK 토큰 / 자원 사용을 분리.

⚠ 검증 환경: Pi 5 (8GB) 권장. Pi 4 4GB 에서는 2개가 현실적 상한.

> 📜 2026-05-16 재작성 라운드 — 1차 라운드의 "역할별 별도 systemd 인스턴스 + 별도 사용자" 패턴 (`/opt/openclaw-{triage,coder,reporter}`) 은 과도하게 복잡. OpenClaw 는 `agents.list[]` 로 한 프로세스 안에서 다중 에이전트를 지원한다.

---

## 시나리오

- "트리아지 봇" + "코딩 봇" + "리포팅 봇" 처럼 책임을 분리해 안전 모델을 다르게 운영
- 각 봇이 다른 모델 (Haiku vs Sonnet vs Opus) / 다른 스킬 화이트리스트 / 다른 채널 라우팅
- 하나의 에이전트가 폭주해도 다른 에이전트는 살아있게 (모델/스킬 격리)

---

## 필요 조건

- Pi 5 (8GB) + NVMe 권장 ([06 — Performance Tuning](../docs/06-performance-tuning.md))
- OpenClaw ≥ 2026.2.6
- 역할별 BYOK 키 (또는 같은 키 공유 + 모델만 다르게)

---

## 단계

### 1) `agents.list[]` 정의

`~/.openclaw/openclaw.json`:

```json5
{
  agents: {
    defaults: {
      workspace: "~/.openclaw/workspace",
    },
    list: [
      {
        name: "triage",
        model: { primary: "anthropic/claude-haiku-4-5-20251001" },
        skills: ["log-triage", "issue-categorize"],
        // triage 는 읽기/요약만 — 쓰기/푸시 스킬 화이트리스트에서 제외
      },
      {
        name: "coder",
        model: {
          primary: "anthropic/claude-sonnet-4-6",
          fallbacks: ["anthropic/claude-opus-4-7"],
        },
        skills: ["cleanup-issue", "review-pr"],
      },
      {
        name: "reporter",
        model: { primary: "anthropic/claude-haiku-4-5-20251001" },
        skills: ["weekly-review", "log-triage"],
        // reporter 는 발행만 — gh pr create 같은 변경 스킬 제외
      },
    ],
  },
}
```

### 2) 채널 라우팅

같은 봇이 메시지를 받았을 때 어느 에이전트가 처리할지:

```json5
{
  channels: {
    telegram: {
      enabled: true,
      botToken: "REPLACE_VIA_ENV:TELEGRAM_BOT_TOKEN",
      // 슬래시 명령에 따라 라우팅
      routing: [
        { match: "^/triage",  agent: "triage" },
        { match: "^/code",    agent: "coder" },
        { match: "^/report",  agent: "reporter" },
        { default: true,      agent: "triage" },  // 기본은 가벼운 모델
      ],
    },
  },
}
```

### 3) 스킬 화이트리스트로 권한 격리

각 스킬의 `SKILL.md` 가 도구 사용 권한을 정의 (`requires.bins`). 에이전트의 `skills:` 배열에 포함된 스킬만 그 에이전트가 호출 가능.

| 에이전트 | 허용 스킬 |
|---|---|
| triage | `log-triage`, `issue-categorize` (읽기만) |
| coder | `cleanup-issue`, `review-pr` (gh / git push 사용) |
| reporter | `weekly-review`, `log-triage` (외부 발행) |

cross-agent 작업 (triage 가 발견 → coder 에게 위임) 은 메시지로:

```bash
# triage 가 본 이슈를 coder 큐로
openclaw message send --agent coder --message "이슈 #42 정리 부탁: <요약>"
```

### 4) 자원 / 시각화

```bash
openclaw agents status      # 에이전트별 호출 수 / 평균 응답 시간 / 에러율
systemctl --user status openclaw     # 단일 프로세스 — 메모리/CPU 통합
```

Pi 5 8GB 기준 3개 에이전트가 동시에 active 일 때 메모리 ~1.5–2GB, CPU 가벼움 (대부분 시간 LLM 응답 대기).

---

## 운영 팁

- **모델 핀 테스트**: triage 를 Haiku 로 돌려도 분류 정확도가 충분한 경우가 많음 → 비용 절감
- **점진 도입**: 처음엔 단일 에이전트 (`agents.defaults`) 로 시작, 안정화되면 list 분리
- **에이전트별 로그**: `journalctl --user -u openclaw | grep 'agent=triage'` 식으로 필터 — OpenClaw 로그가 agent 태그를 붙임 (확인 필요)
- **공유 워크스페이스**: 기본은 한 workspace 공유. 충돌이 생기면 에이전트별 `workspace:` 분리

---

## 알려진 한계

- **BYOK 토큰 공유**: 같은 Anthropic 계정의 API key 를 N개 에이전트가 동시 사용 시 합산 한도. 별 계정을 쓰려면 각 에이전트에 별 `apiKey:` 명시
- **레이트 리밋 합산**: 여러 에이전트가 같은 계정의 키를 쓰면 한도 합산. 작업 처리량 미리 계산
- **메모리 압박**: Pi 4 4GB 는 2개도 빠듯. zram / swap 필수 ([06 §4](../docs/06-performance-tuning.md))
- **모든 에이전트가 같은 프로세스**: OpenClaw 본체가 죽으면 모두 멈춤. systemd `Restart=on-failure` + watchdog 으로 보강
- **권한 격리는 스킬 화이트리스트 수준** — OS-level 격리 (별 사용자 / 별 cgroup) 가 필요하면 옵션 B (1차 라운드의 별 systemd 인스턴스) 로 회귀. 단 복잡도 ↑↑

---

## 다음

- [자율 코딩 루프](./auto-coding-loop.md)
- [06 — Performance Tuning](../docs/06-performance-tuning.md)
- [07 — Hardening](../docs/07-openclaw-hardening.md)

#!/usr/bin/env bash
# USAGE: bash run.sh
#
# hello-agent 끝-끝 검증. 본 디렉토리의 SKILL.md 를 ~/.openclaw/skills/hello/ 로
# 설치하고, openclaw agent --message "hello" 응답이 정확히 'ok' 인지 확인한다.

set -euo pipefail

if [[ -t 1 ]]; then
    C_OK="$(tput setaf 2)"; C_WARN="$(tput setaf 3)"; C_ERR="$(tput setaf 1)"
    C_INFO="$(tput setaf 6)"; C_OFF="$(tput sgr0)"
else
    C_OK=""; C_WARN=""; C_ERR=""; C_INFO=""; C_OFF=""
fi
log() { printf '%s[hello]%s %s\n' "$C_INFO" "$C_OFF" "$*"; }
ok()  { printf '%s[ok]%s %s\n'    "$C_OK"   "$C_OFF" "$*"; }
warn(){ printf '%s[warn]%s %s\n'  "$C_WARN" "$C_OFF" "$*" >&2; }
die() { printf '%s[err]%s %s\n'   "$C_ERR"  "$C_OFF" "$*" >&2; exit 1; }

command -v openclaw >/dev/null 2>&1 || die "openclaw 미설치 — install-openclaw.sh 먼저."

HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_SRC="$HERE/SKILL.md"
SKILL_DST="$HOME/.openclaw/skills/hello"

[[ -f "$SKILL_SRC" ]] || die "SKILL.md 가 없습니다: $SKILL_SRC"

# 1) 스킬 설치 (멱등)
log "스킬 설치: $SKILL_DST"
mkdir -p "$SKILL_DST"
cp -f "$SKILL_SRC" "$SKILL_DST/SKILL.md"
ok "스킬 설치 완료"

# 2) Gateway 가 떠 있는지 확인 — onboard 가 daemon 으로 띄웠으면 통과
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
if ! (echo >/dev/tcp/127.0.0.1/"$GATEWAY_PORT") 2>/dev/null; then
    warn "Gateway 가 127.0.0.1:$GATEWAY_PORT 에 안 떠 있습니다. 별도 창에서:"
    warn "  openclaw gateway --port $GATEWAY_PORT --verbose"
    die  "Gateway 기동 후 다시 실행하세요."
fi
ok "Gateway 응답: 127.0.0.1:$GATEWAY_PORT"

# 3) agent 호출 + 응답 캡처
log "openclaw agent --message 'hello' 호출..."
RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$RESPONSE_FILE"' EXIT

if ! openclaw agent --message "hello" --thinking high > "$RESPONSE_FILE" 2>&1; then
    cat "$RESPONSE_FILE" >&2
    die "openclaw agent 호출 실패 (exit code != 0)"
fi

# 4) 응답이 정확히 'ok' 인지 (앞뒤 공백 제거)
RESP="$(tr -d '[:space:]' < "$RESPONSE_FILE")"
if [[ "$RESP" != "ok" ]]; then
    warn "예상 응답: 'ok', 실제 응답:"
    cat "$RESPONSE_FILE" >&2
    die "응답이 정확한 'ok' 가 아닙니다. SKILL.md description / model primary 점검."
fi
ok "응답 일치: 'ok'"

# 5) (선택) gateway 로그에 매칭 흔적 — 사용 가능한 경우만
if command -v journalctl >/dev/null 2>&1; then
    if journalctl --user -u openclaw -n 50 --no-pager 2>/dev/null \
       | grep -qi 'skill.*hello\|hello.*skill'; then
        ok "gateway 로그에 skill=hello 매칭 확인"
    else
        warn "(참고) journald 의 openclaw 로그에 매칭 흔적 없음. --user systemd 미설정일 수 있음 (필수 아님)"
    fi
fi

ok "끝-끝 검증 통과 ✅"
log "다음: docs/07-openclaw-hardening.md 통독 후 channels.* 활성화로 진행"

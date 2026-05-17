#!/usr/bin/env bash
# USAGE: bash scripts/healthcheck.sh
#
# Pi 위에서 OpenClaw + Claude Code 운영 상태를 점검한다.
# 모두 통과하면 종료코드 0, 하나라도 실패면 1, 경고만 있으면 2.
#
# 환경변수:
#   HC_DISK_FREE_GB   디스크 여유공간 임계 (GB, 기본 5)
#   HC_MEM_FREE_MB    메모리 여유공간 임계 (MB, 기본 256)
#   HC_TOKEN_MAX_AGE  OAuth 토큰 최대 나이 (일, 기본 60)

set -uo pipefail   # -e 는 의도적으로 빼서 모든 체크를 끝까지 돌린다

if [[ -t 1 ]]; then
    C_OK="$(tput setaf 2)"; C_WARN="$(tput setaf 3)"; C_ERR="$(tput setaf 1)"
    C_INFO="$(tput setaf 6)"; C_OFF="$(tput sgr0)"
else
    C_OK=""; C_WARN=""; C_ERR=""; C_INFO=""; C_OFF=""
fi
log()  { printf '%s[hc]%s %s\n'    "$C_INFO" "$C_OFF" "$*"; }
pass() { printf '%s[PASS]%s %s\n'  "$C_OK"   "$C_OFF" "$*"; }
warn() { printf '%s[WARN]%s %s\n'  "$C_WARN" "$C_OFF" "$*" >&2; warns=$((warns+1)); }
fail() { printf '%s[FAIL]%s %s\n'  "$C_ERR"  "$C_OFF" "$*" >&2; fails=$((fails+1)); }

DISK_FREE_GB="${HC_DISK_FREE_GB:-5}"
MEM_FREE_MB="${HC_MEM_FREE_MB:-256}"
TOKEN_MAX_AGE="${HC_TOKEN_MAX_AGE:-60}"

fails=0
warns=0

# ---------- 1. 바이너리 ------------------------------------------------------
if command -v claude >/dev/null 2>&1; then
    pass "claude: $(claude --version 2>/dev/null || echo '?')"
else
    fail "claude 바이너리 없음"
fi

if command -v openclaw >/dev/null 2>&1; then
    pass "openclaw: $(openclaw --version 2>/dev/null || echo '?')"
else
    warn "openclaw 바이너리 없음 (아직 설치 전이면 무시)"
fi

# ---------- 2. Claude CLI 자격증명 (OpenClaw 위임 모드 시 필수) -------------
# OpenClaw 의 agentRuntime.id="claude-cli" 모드일 때 ~/.claude/.credentials.json 을
# 백엔드 인증으로 위임 사용. BYOK 모드면 본 절은 무관.
CRED="$HOME/.claude/.credentials.json"
[[ -f "$CRED" ]] || CRED="$HOME/.claude/credentials.json"   # 2.1.x 와 구버전 모두 지원
if [[ -f "$CRED" ]]; then
    perm="$(stat -c '%a' "$CRED" 2>/dev/null || stat -f '%Lp' "$CRED")"
    if [[ "$perm" != "600" ]]; then
        warn "Claude CLI credentials 권한이 ${perm} (권장: 600)"
    else
        pass "Claude CLI credentials 권한 600 OK"
    fi
    age_days=$(( ( $(date +%s) - $(stat -c '%Y' "$CRED" 2>/dev/null || stat -f '%m' "$CRED") ) / 86400 ))
    if (( age_days > TOKEN_MAX_AGE )); then
        warn "Claude CLI 토큰 ${age_days}일 경과 (재인증 권장 — 위임 모드 사용 시)"
    else
        pass "Claude CLI 토큰 나이 ${age_days}일 (한도 ${TOKEN_MAX_AGE}일)"
    fi
else
    warn "Claude CLI 자격증명 없음 ($CRED). OpenClaw BYOK 모드면 무시, 위임 모드면 'claude /login' 또는 'claude setup-token' 필요."
fi

# ~/.claude 디렉토리 권한
if [[ -d "$HOME/.claude" ]]; then
    dperm="$(stat -c '%a' "$HOME/.claude" 2>/dev/null || stat -f '%Lp' "$HOME/.claude")"
    if [[ "$dperm" != "700" ]]; then
        warn "~/.claude 권한이 ${dperm} (권장: 700)"
    fi
fi

# ---------- 2-bis. OpenClaw 설정 / BYOK ------------------------------------
OC_CFG="$HOME/.openclaw/openclaw.json"
if [[ -f "$OC_CFG" ]]; then
    pass "OpenClaw 설정 존재: $OC_CFG"

    # 디렉토리 권한
    ocperm="$(stat -c '%a' "$HOME/.openclaw" 2>/dev/null || stat -f '%Lp' "$HOME/.openclaw")"
    if [[ "$ocperm" != "700" ]]; then
        warn "~/.openclaw 권한이 ${ocperm} (권장: 700 — 평문 자격증명 보호)"
    fi
    fperm="$(stat -c '%a' "$OC_CFG" 2>/dev/null || stat -f '%Lp' "$OC_CFG")"
    if [[ "$fperm" != "600" ]]; then
        warn "openclaw.json 권한이 ${fperm} (권장: 600)"
    fi

    # gateway 보안 베이스라인 — jq 가 있으면 점검
    if command -v jq >/dev/null 2>&1; then
        host="$(jq -r '.gateway.host // "?"' "$OC_CFG" 2>/dev/null)"
        bind="$(jq -r '.gateway.bind // "?"' "$OC_CFG" 2>/dev/null)"
        if [[ "$host" != "127.0.0.1" && "$host" != "localhost" ]] || [[ "$bind" != "loopback" ]]; then
            warn "gateway.host=${host} / bind=${bind} — loopback 권장 (docs/07 §2)"
        else
            pass "gateway 바인딩 loopback OK"
        fi
    fi
else
    warn "OpenClaw 설정 없음 ($OC_CFG). openclaw onboard 미수행."
fi

# ---------- 3. 디스크 / 메모리 ----------------------------------------------
free_gb="$(df -BG --output=avail "$HOME" 2>/dev/null | tail -1 | tr -dc '0-9')"
if [[ -n "$free_gb" ]]; then
    if (( free_gb < DISK_FREE_GB )); then
        fail "디스크 여유 ${free_gb}GB < ${DISK_FREE_GB}GB"
    else
        pass "디스크 여유 ${free_gb}GB"
    fi
else
    warn "디스크 여유 측정 실패"
fi

if [[ -r /proc/meminfo ]]; then
    mem_avail_kb="$(awk '/MemAvailable/ {print $2}' /proc/meminfo)"
    mem_avail_mb=$(( mem_avail_kb / 1024 ))
    if (( mem_avail_mb < MEM_FREE_MB )); then
        fail "메모리 여유 ${mem_avail_mb}MB < ${MEM_FREE_MB}MB"
    else
        pass "메모리 여유 ${mem_avail_mb}MB"
    fi
fi

# ---------- 4. 네트워크 (Anthropic 도달성) ----------------------------------
if command -v curl >/dev/null 2>&1; then
    if curl -fsS --max-time 5 -o /dev/null https://api.anthropic.com/v1/healthcheck 2>/dev/null \
        || curl -fsS --max-time 5 -o /dev/null https://www.anthropic.com 2>/dev/null; then
        pass "anthropic.com 도달 가능"
    else
        warn "anthropic.com 도달 실패 (네트워크/방화벽 확인)"
    fi
fi

# ---------- 5. systemd 유닛 (있으면) ----------------------------------------
# user 모드 (openclaw onboard --install-daemon 가 만든 유닛) 우선, 없으면 system 모드.
if command -v systemctl >/dev/null 2>&1; then
    found_unit=0
    if systemctl --user list-unit-files openclaw.service >/dev/null 2>&1 \
       && systemctl --user list-unit-files openclaw.service | grep -q openclaw.service; then
        found_unit=1
        if systemctl --user is-active --quiet openclaw.service; then
            pass "openclaw.service (user) active"
        else
            warn "openclaw.service (user) inactive: $(systemctl --user is-active openclaw.service 2>/dev/null || echo unknown)"
        fi
    fi
    if systemctl list-unit-files openclaw.service >/dev/null 2>&1 \
       && systemctl list-unit-files openclaw.service | grep -q openclaw.service; then
        found_unit=1
        if systemctl is-active --quiet openclaw.service; then
            pass "openclaw.service (system) active"
        else
            warn "openclaw.service (system) inactive: $(systemctl is-active openclaw.service)"
        fi
    fi
    if [[ "$found_unit" -eq 0 ]]; then
        warn "openclaw.service 유닛 없음 (user/system 양쪽). foreground 'openclaw gateway' 로 가동 중일 수 있음."
    fi

    # gateway 포트 응답 점검 (loopback)
    GW_PORT="${HC_GATEWAY_PORT:-18789}"
    if (echo >/dev/tcp/127.0.0.1/"$GW_PORT") 2>/dev/null; then
        pass "gateway 응답: 127.0.0.1:$GW_PORT"
    else
        warn "gateway 127.0.0.1:$GW_PORT 응답 없음 (openclaw 미기동 또는 다른 포트)"
    fi
fi

# ---------- 결과 ------------------------------------------------------------
log "결과: FAIL=${fails}, WARN=${warns}"
if (( fails > 0 )); then
    exit 1
elif (( warns > 0 )); then
    exit 2
else
    exit 0
fi

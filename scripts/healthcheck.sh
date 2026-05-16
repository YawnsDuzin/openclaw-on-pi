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

# ---------- 2. OAuth 자격증명 -----------------------------------------------
CRED="$HOME/.claude/credentials.json"
if [[ -f "$CRED" ]]; then
    perm="$(stat -c '%a' "$CRED" 2>/dev/null || stat -f '%Lp' "$CRED")"
    if [[ "$perm" != "600" ]]; then
        warn "credentials.json 권한이 ${perm} (권장: 600)"
    else
        pass "credentials.json 권한 600 OK"
    fi
    age_days=$(( ( $(date +%s) - $(stat -c '%Y' "$CRED" 2>/dev/null || stat -f '%m' "$CRED") ) / 86400 ))
    if (( age_days > TOKEN_MAX_AGE )); then
        warn "OAuth 토큰 ${age_days}일 경과 (재인증 권장)"
    else
        pass "OAuth 토큰 나이 ${age_days}일 (한도 ${TOKEN_MAX_AGE}일)"
    fi
else
    fail "OAuth 자격증명 없음 ($CRED). oauth-tunnel.sh 절차 필요."
fi

# ~/.claude 디렉토리 권한
if [[ -d "$HOME/.claude" ]]; then
    dperm="$(stat -c '%a' "$HOME/.claude" 2>/dev/null || stat -f '%Lp' "$HOME/.claude")"
    if [[ "$dperm" != "700" ]]; then
        warn "~/.claude 권한이 ${dperm} (권장: 700)"
    fi
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
if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files openclaw.service >/dev/null 2>&1; then
        if systemctl is-active --quiet openclaw.service; then
            pass "openclaw.service active"
        else
            warn "openclaw.service inactive ($(systemctl is-active openclaw.service))"
        fi
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

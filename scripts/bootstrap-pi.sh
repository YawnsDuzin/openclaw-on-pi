#!/usr/bin/env bash
# USAGE: bash scripts/bootstrap-pi.sh
#
# Raspberry Pi (Pi 4 / Pi 5, ARM64, Bookworm 또는 Ubuntu 24.04) 를
# OpenClaw + Claude Code 운영용 베이스로 셋업한다.
#
# 멱등(idempotent): 이미 설치된 패키지는 건너뛴다.
# 비파괴: 기존 사용자/홈/네트워크 설정을 수정하지 않는다.

set -euo pipefail

# ---------- 출력 헬퍼 -------------------------------------------------------
if [[ -t 1 ]]; then
    C_OK="$(tput setaf 2)"; C_WARN="$(tput setaf 3)"; C_ERR="$(tput setaf 1)"
    C_INFO="$(tput setaf 6)"; C_OFF="$(tput sgr0)"
else
    C_OK=""; C_WARN=""; C_ERR=""; C_INFO=""; C_OFF=""
fi
log()  { printf '%s[bootstrap]%s %s\n' "$C_INFO" "$C_OFF" "$*"; }
ok()   { printf '%s[ok]%s %s\n'        "$C_OK"   "$C_OFF" "$*"; }
warn() { printf '%s[warn]%s %s\n'      "$C_WARN" "$C_OFF" "$*" >&2; }
die()  { printf '%s[err]%s %s\n'       "$C_ERR"  "$C_OFF" "$*" >&2; exit 1; }

# ---------- 사전 점검 -------------------------------------------------------
[[ "$(id -u)" -eq 0 ]] && die "root 로 직접 실행 금지. 일반 유저 + sudo 사용."
command -v sudo >/dev/null 2>&1 || die "sudo 가 필요합니다."

ARCH="$(uname -m)"
case "$ARCH" in
    aarch64|arm64) ok "ARM64 아키텍처 감지: $ARCH" ;;
    x86_64)        warn "x86_64 환경. README 는 ARM64 Pi 를 전제하지만 진행은 가능." ;;
    *)             die "지원하지 않는 아키텍처: $ARCH" ;;
esac

if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    log "OS: ${PRETTY_NAME:-unknown}"
fi

# ---------- apt/dpkg 사전 점검 -----------------------------------------------
# 자주 만나는 사전 함정 3종:
#   1) 이전 apt/dpkg 가 중단되어 half-configured 상태로 남음 → dpkg --audit 가 항목을 출력
#   2) 다른 apt 프로세스(unattended-upgrades 등) 가 dpkg 락 점유 중
#   3) 디스크 부족으로 apt 가 실패
APT_LOCK="/var/lib/dpkg/lock-frontend"

log "apt/dpkg 사전 점검..."

# half-configured 상태 감지: 출력이 있으면 비정상
if sudo dpkg --audit 2>/dev/null | grep -q .; then
    warn "dpkg 가 half-configured 상태입니다. 자동 복구를 시도합니다."
    log "  → sudo dpkg --configure -a"
    if ! sudo dpkg --configure -a; then
        die "dpkg --configure -a 실패. 수동 진단 필요 (troubleshooting.md C4 참고)."
    fi
    sudo apt-get install -f -y || warn "apt-get install -f 가 일부 실패 — 계속 진행"
    ok "dpkg 상태 복구 완료"
fi

# 락 점유 감지 (fuser 가 있으면 사용, 없으면 lsof, 둘 다 없으면 스킵)
if [[ -e "$APT_LOCK" ]]; then
    if command -v fuser >/dev/null 2>&1; then
        if sudo fuser "$APT_LOCK" >/dev/null 2>&1; then
            sudo fuser -v "$APT_LOCK" >&2 || true
            die "$APT_LOCK 가 다른 프로세스에 점유 중. 위 PID 종료 또는 완료를 대기한 뒤 재실행."
        fi
    elif command -v lsof >/dev/null 2>&1; then
        if sudo lsof "$APT_LOCK" >/dev/null 2>&1; then
            sudo lsof "$APT_LOCK" >&2 || true
            die "$APT_LOCK 가 다른 프로세스에 점유 중. 위 PID 종료 또는 완료를 대기한 뒤 재실행."
        fi
    fi
fi

# 디스크 여유 (루트 파티션 1GB 미만이면 경고)
ROOT_AVAIL_KB="$(df -P / | awk 'NR==2 {print $4}')"
if [[ "${ROOT_AVAIL_KB:-0}" -lt 1048576 ]]; then
    warn "루트 파티션 여유 < 1GB. apt 가 중간에 실패할 수 있습니다."
    warn "  → sudo apt-get clean; sudo journalctl --vacuum-size=200M"
fi
ok "사전 점검 통과"

# ---------- 패키지 설치 -----------------------------------------------------
APT_PKGS=(
    build-essential
    ca-certificates
    curl
    git
    gnupg
    jq
    python3
    python3-pip
    python3-venv
    tmux
    unzip
    htop
    rsync
)

log "apt 업데이트 + 핵심 패키지 설치..."
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${APT_PKGS[@]}"
ok "apt 패키지 완료"

# ---------- Node LTS (NodeSource) ------------------------------------------
NODE_MAJOR="${NODE_MAJOR:-20}"
if command -v node >/dev/null 2>&1 && node --version | grep -q "^v${NODE_MAJOR}\."; then
    ok "Node.js v${NODE_MAJOR} 이미 설치됨: $(node --version)"
else
    log "Node.js v${NODE_MAJOR} (NodeSource) 설치..."
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | sudo -E bash -
    sudo apt-get install -y nodejs
    ok "Node.js 설치: $(node --version)"
fi

# ---------- 운영 디렉토리 ----------------------------------------------------
USER_HOME="$(getent passwd "$USER" | cut -d: -f6)"
# 작업 베이스: 기본 $HOME/dzp_main/program (사용자 dzp 기준 /home/dzp/dzp_main/program)
# 다른 경로를 쓰려면 OPENCLAW_PROGRAM_BASE 환경변수로 오버라이드.
PROGRAM_BASE="${OPENCLAW_PROGRAM_BASE:-$USER_HOME/dzp_main/program}"
WORK_DIR="$PROGRAM_BASE/openclaw-work"

mkdir -p "$USER_HOME/.claude" "$WORK_DIR" "$USER_HOME/.local/bin"
chmod 700 "$USER_HOME/.claude"
ok "디렉토리 준비 완료 (~/.claude, $WORK_DIR)"

# ---------- PATH 점검 -------------------------------------------------------
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$USER_HOME/.local/bin"; then
    warn "~/.local/bin 가 PATH 에 없습니다. ~/.bashrc 또는 ~/.zshrc 에 추가하세요:"
    warn '  export PATH="$HOME/.local/bin:$PATH"'
fi

ok "bootstrap 완료. 다음 단계:"
log "  1) bash scripts/install-claude-code.sh"
log "  2) bash scripts/install-openclaw.sh"
log "  3) bash scripts/oauth-tunnel.sh   # OAuth 1회 인증"

#!/usr/bin/env bash
# USAGE: bash scripts/install-openclaw.sh
#
# OpenClaw 설치. 본 저장소는 OpenClaw 의 공식 배포 채널을 추상화하여 호출한다.
# 환경변수로 설치 모드를 강제할 수 있다.
#
#   OPENCLAW_INSTALL_MODE = pipx | pip | git   (기본: 자동 감지)
#   OPENCLAW_GIT_URL      = OpenClaw 소스 저장소 URL  (mode=git 일 때)
#   OPENCLAW_REF          = git ref (브랜치/태그/커밋, 기본 main)
#   OPENCLAW_VENV         = mode=pip 일 때 사용할 venv 경로 (기본 ~/.openclaw-venv)
#
# OpenClaw 의 공식 설치 절차가 확정되면 본 스크립트의 분기를 단순화하라.

set -euo pipefail

if [[ -t 1 ]]; then
    C_OK="$(tput setaf 2)"; C_WARN="$(tput setaf 3)"; C_ERR="$(tput setaf 1)"
    C_INFO="$(tput setaf 6)"; C_OFF="$(tput sgr0)"
else
    C_OK=""; C_WARN=""; C_ERR=""; C_INFO=""; C_OFF=""
fi
log()  { printf '%s[openclaw-install]%s %s\n' "$C_INFO" "$C_OFF" "$*"; }
ok()   { printf '%s[ok]%s %s\n'               "$C_OK"   "$C_OFF" "$*"; }
warn() { printf '%s[warn]%s %s\n'             "$C_WARN" "$C_OFF" "$*" >&2; }
die()  { printf '%s[err]%s %s\n'              "$C_ERR"  "$C_OFF" "$*" >&2; exit 1; }

MODE="${OPENCLAW_INSTALL_MODE:-auto}"
GIT_URL="${OPENCLAW_GIT_URL:-https://github.com/openclaw/openclaw.git}"
GIT_REF="${OPENCLAW_REF:-main}"
VENV="${OPENCLAW_VENV:-$HOME/.openclaw-venv}"

# auto 감지: pipx > pip > git
if [[ "$MODE" == "auto" ]]; then
    if command -v pipx >/dev/null 2>&1; then
        MODE="pipx"
    elif command -v python3 >/dev/null 2>&1; then
        MODE="pip"
    else
        MODE="git"
    fi
fi
log "설치 모드: $MODE"

case "$MODE" in
    pipx)
        log "pipx 로 openclaw 설치..."
        pipx install openclaw || pipx upgrade openclaw
        ;;
    pip)
        log "venv ($VENV) 생성 + pip install openclaw..."
        if [[ ! -d "$VENV" ]]; then
            python3 -m venv "$VENV"
        fi
        # shellcheck disable=SC1091
        . "$VENV/bin/activate"
        pip install --upgrade pip
        pip install --upgrade openclaw
        deactivate
        # ~/.local/bin 에 진입점 심볼릭링크
        mkdir -p "$HOME/.local/bin"
        if [[ -x "$VENV/bin/openclaw" ]]; then
            ln -sf "$VENV/bin/openclaw" "$HOME/.local/bin/openclaw"
            ok "심볼릭링크: ~/.local/bin/openclaw -> $VENV/bin/openclaw"
        fi
        ;;
    git)
        SRC="$HOME/src/openclaw"
        log "git clone $GIT_URL ($GIT_REF) → $SRC"
        if [[ -d "$SRC/.git" ]]; then
            git -C "$SRC" fetch --all --prune
            git -C "$SRC" checkout "$GIT_REF"
            git -C "$SRC" pull --ff-only || warn "fast-forward 실패 (수동 확인 필요)"
        else
            mkdir -p "$(dirname "$SRC")"
            git clone --depth 1 --branch "$GIT_REF" "$GIT_URL" "$SRC"
        fi
        warn "git 모드는 OpenClaw 빌드/설치 절차를 추가로 따라야 합니다."
        warn "  → $SRC/README.md 참고."
        ;;
    *)
        die "알 수 없는 모드: $MODE"
        ;;
esac

if command -v openclaw >/dev/null 2>&1; then
    ok "openclaw 사용 가능: $(openclaw --version 2>/dev/null || echo 'version 명령 없음')"
else
    warn "openclaw 명령을 PATH 에서 찾지 못했습니다. 위 메시지를 확인하세요."
fi

PROGRAM_BASE="${OPENCLAW_PROGRAM_BASE:-$HOME/dzp_main/program}"
log "다음 단계: configs/openclaw.example.yaml → $PROGRAM_BASE/openclaw-work/openclaw.yaml 로 복사 후 수정"

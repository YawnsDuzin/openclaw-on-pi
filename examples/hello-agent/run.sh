#!/usr/bin/env bash
# USAGE: bash run.sh
#
# hello-agent 1회 트리거. 현재 디렉토리(`examples/hello-agent`) 가
# git 저장소여야 한다 (스크립트가 알아서 init 한다).

set -euo pipefail

if [[ -t 1 ]]; then
    C_OK="$(tput setaf 2)"; C_INFO="$(tput setaf 6)"; C_OFF="$(tput sgr0)"
else
    C_OK=""; C_INFO=""; C_OFF=""
fi
log() { printf '%s[hello]%s %s\n' "$C_INFO" "$C_OFF" "$*"; }
ok()  { printf '%s[ok]%s %s\n'    "$C_OK"   "$C_OFF" "$*"; }

command -v openclaw >/dev/null 2>&1 \
    || { echo "openclaw 미설치 — install-openclaw.sh 먼저"; exit 1; }
command -v claude   >/dev/null 2>&1 \
    || { echo "claude 미설치 — install-claude-code.sh 먼저"; exit 1; }

# git 저장소 보장
if [[ ! -d .git ]]; then
    log "git 저장소 초기화"
    git init -q
    git add .
    git -c user.email="hello@openclaw.local" -c user.name="hello-agent" \
        commit -q -m "init: hello-agent demo"
fi

log "task enqueue + run --once"
openclaw enqueue --queue default --task hello-write --tasks-file ./tasks.yaml
openclaw run --once --log-level debug

ok "완료. git log 마지막 커밋 확인:"
git log -1 --pretty=fuller

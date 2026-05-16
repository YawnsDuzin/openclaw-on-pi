#!/usr/bin/env bash
# USAGE:
#   # Pi (헤드리스) 에서 실행:
#   bash scripts/oauth-tunnel.sh [LOCAL_PORT]
#
# Claude Code OAuth 콜백은 브라우저가 localhost:<port> 로 리다이렉트되는 방식이다.
# Pi 가 헤드리스라 브라우저가 없을 때, 로컬 PC 의 브라우저로 콜백을 받아주려면
# SSH 역포트포워딩이 필요하다.
#
# 흐름:
#   1) 로컬 PC 에서 SSH 세션을 열 때:
#        ssh -L 54545:localhost:54545 pi@<pi-host>
#   2) Pi 에 들어와서 본 스크립트로 안내 출력 + claude login 시작 안내
#   3) `claude login` 가 출력하는 https://... URL 을 복사하여
#      로컬 PC 브라우저에 붙여넣기 → 콜백이 localhost:54545 로 들어가
#      SSH 터널을 통해 Pi 로 전달됨
#   4) ~/.claude/credentials.json 생성 확인
#
# 본 스크립트는 터널을 직접 열지 않는다 (역할: 안내 + 사전 점검). 터널은
# 사용자가 SSH 클라이언트에서 -L 로 직접 여는 것이 가장 확실하기 때문.

set -euo pipefail

if [[ -t 1 ]]; then
    C_OK="$(tput setaf 2)"; C_WARN="$(tput setaf 3)"; C_ERR="$(tput setaf 1)"
    C_INFO="$(tput setaf 6)"; C_OFF="$(tput sgr0)"
else
    C_OK=""; C_WARN=""; C_ERR=""; C_INFO=""; C_OFF=""
fi
log()  { printf '%s[oauth]%s %s\n' "$C_INFO" "$C_OFF" "$*"; }
ok()   { printf '%s[ok]%s %s\n'    "$C_OK"   "$C_OFF" "$*"; }
warn() { printf '%s[warn]%s %s\n'  "$C_WARN" "$C_OFF" "$*" >&2; }
die()  { printf '%s[err]%s %s\n'   "$C_ERR"  "$C_OFF" "$*" >&2; exit 1; }

PORT="${1:-54545}"

# claude 가 PATH 에 없으면, 흔한 위치(~/.npm-global/bin)에 있는지 확인하여
# "미설치" 와 "PATH 누락" 을 구분해 안내한다.
if ! command -v claude >/dev/null 2>&1; then
    NPM_GLOBAL_PREFIX="${NPM_GLOBAL_PREFIX:-$HOME/.npm-global}"
    if [[ -x "$NPM_GLOBAL_PREFIX/bin/claude" ]]; then
        warn "claude 는 설치되어 있으나 PATH 에 없습니다 ($NPM_GLOBAL_PREFIX/bin/claude)."
        warn "현재 셸에 적용:"
        warn "  export PATH=\"$NPM_GLOBAL_PREFIX/bin:\$PATH\""
        warn "영구 적용 (idempotent):"
        warn "  grep -qxF 'export PATH=\"\$HOME/.npm-global/bin:\$PATH\"' ~/.bashrc \\"
        warn "    || echo 'export PATH=\"\$HOME/.npm-global/bin:\$PATH\"' >> ~/.bashrc"
        warn "  source ~/.bashrc"
        die  "PATH 적용 후 다시 실행하세요."
    fi
    die "claude 바이너리가 없습니다. install-claude-code.sh 먼저."
fi

# 이미 인증되어 있는지 가벼운 점검
CRED="$HOME/.claude/credentials.json"
if [[ -f "$CRED" ]]; then
    warn "이미 OAuth 자격증명이 있습니다: $CRED"
    warn "재인증하려면 먼저 파일을 백업하세요:"
    warn "  mv $CRED ${CRED}.bak.\$(date +%s)"
fi

cat <<EOF

${C_INFO}========================================================================${C_OFF}
${C_INFO} Claude Code 헤드리스 OAuth 인증 가이드${C_OFF}
${C_INFO}========================================================================${C_OFF}

이 Pi 는 브라우저가 없는 헤드리스 환경으로 가정합니다.
다음 절차로 로컬 PC 의 브라우저를 빌려 OAuth 콜백을 처리합니다.

[ 1단계 — 로컬 PC 에서 SSH 세션 열기 ]

  로컬 PC (= 브라우저가 있는 머신) 의 터미널에서 새 SSH 세션을 다음처럼 엽니다:

    ssh -L ${PORT}:localhost:${PORT} ${USER}@<this-pi-host>

  -L 옵션이 핵심입니다. 이미 열린 SSH 세션이 있어도 새로 -L 로 다시 여세요.

[ 2단계 — Pi 에서 claude login 실행 ]

  본 SSH 세션에서:

    claude login

  Claude Code 가 'Open this URL in your browser:' 와 함께
  https://... URL 을 출력합니다.

[ 3단계 — 로컬 PC 브라우저에서 URL 열기 ]

  출력된 URL 을 로컬 PC 의 브라우저에 붙여넣고 로그인.
  Anthropic 콘솔이 localhost:${PORT}/callback?... 으로 리다이렉트하면,
  SSH 역터널을 타고 Pi 의 claude 프로세스가 토큰을 수신합니다.

[ 4단계 — 자격증명 확인 ]

  생성 확인:
    ls -la ~/.claude/credentials.json
  권한 점검 (반드시 600):
    chmod 600 ~/.claude/credentials.json
  디렉토리 권한:
    chmod 700 ~/.claude

[ 트러블슈팅 ]

  - "Address already in use" : 로컬 PC 에서 ${PORT} 포트가 점유됨. 다른 포트로:
      bash scripts/oauth-tunnel.sh 55656
      ssh -L 55656:localhost:55656 ${USER}@<this-pi-host>
  - 콜백이 안 옴 : SSH 세션의 -L 이 제대로 걸렸는지 'ss -tlnp | grep ${PORT}' 로 확인
  - 토큰 만료 : 같은 절차로 재인증 (자동 갱신은 미지원)

준비가 되면 본 SSH 세션에서:

    ${C_OK}claude login${C_OFF}

EOF

ok "안내 출력 완료. 위 절차대로 진행하세요."

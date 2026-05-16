#!/usr/bin/env bash
# USAGE: bash scripts/install-claude-code.sh [VERSION]
#
# Claude Code CLI (npm 패키지 @anthropic-ai/claude-code) 설치.
# 인자로 버전을 주면 해당 버전 핀, 아니면 latest.
#
# 환경변수:
#   NPM_GLOBAL_PREFIX  — 사용자 글로벌 npm prefix (기본 ~/.npm-global)
#                       sudo 없이 글로벌 설치하려고 분리.

set -euo pipefail

if [[ -t 1 ]]; then
    C_OK="$(tput setaf 2)"; C_WARN="$(tput setaf 3)"; C_ERR="$(tput setaf 1)"
    C_INFO="$(tput setaf 6)"; C_OFF="$(tput sgr0)"
else
    C_OK=""; C_WARN=""; C_ERR=""; C_INFO=""; C_OFF=""
fi
log()  { printf '%s[claude-install]%s %s\n' "$C_INFO" "$C_OFF" "$*"; }
ok()   { printf '%s[ok]%s %s\n'             "$C_OK"   "$C_OFF" "$*"; }
warn() { printf '%s[warn]%s %s\n'           "$C_WARN" "$C_OFF" "$*" >&2; }
die()  { printf '%s[err]%s %s\n'            "$C_ERR"  "$C_OFF" "$*" >&2; exit 1; }

VERSION="${1:-latest}"
PKG="@anthropic-ai/claude-code"

command -v node >/dev/null 2>&1 || die "Node.js 가 없습니다. bootstrap-pi.sh 를 먼저 실행하세요."
command -v npm  >/dev/null 2>&1 || die "npm 이 없습니다. bootstrap-pi.sh 를 먼저 실행하세요."

# 글로벌 prefix 를 사용자 홈으로 (sudo 없이 설치)
NPM_GLOBAL_PREFIX="${NPM_GLOBAL_PREFIX:-$HOME/.npm-global}"
mkdir -p "$NPM_GLOBAL_PREFIX/bin"
npm config set prefix "$NPM_GLOBAL_PREFIX"
export PATH="$NPM_GLOBAL_PREFIX/bin:$PATH"

log "$PKG@$VERSION 설치 중 (prefix=$NPM_GLOBAL_PREFIX)..."
npm install -g "${PKG}@${VERSION}"

if ! command -v claude >/dev/null 2>&1; then
    warn "claude 바이너리를 PATH 에서 찾지 못했습니다. 다음 줄을 ~/.bashrc 에 추가하세요:"
    warn "  export PATH=\"$NPM_GLOBAL_PREFIX/bin:\$PATH\""
    die  "PATH 수정 후 다시 실행하세요."
fi

ok "설치 완료: $(claude --version 2>/dev/null || echo '버전 확인 실패')"

# ---------- PATH 영구 등록 --------------------------------------------------
# 본 스크립트의 export PATH 는 서브셸에서만 유효. 부모 셸과 다음 로그인을
# 위해 사용자의 셸 rc 에 idempotent 하게 추가한다.
PATH_LINE="export PATH=\"$NPM_GLOBAL_PREFIX/bin:\$PATH\""
RC_FILES=()
[[ -f "$HOME/.bashrc" ]] && RC_FILES+=("$HOME/.bashrc")
[[ -f "$HOME/.zshrc"  ]] && RC_FILES+=("$HOME/.zshrc")
# rc 가 하나도 없으면 .bashrc 신규 생성
[[ ${#RC_FILES[@]} -eq 0 ]] && { touch "$HOME/.bashrc"; RC_FILES+=("$HOME/.bashrc"); }

for RC in "${RC_FILES[@]}"; do
    if grep -qxF "$PATH_LINE" "$RC" 2>/dev/null; then
        log "PATH 이미 등록됨: $RC"
    else
        printf '\n# Added by openclaw-on-pi install-claude-code.sh\n%s\n' "$PATH_LINE" >> "$RC"
        ok "PATH 영구 등록: $RC"
    fi
done

cat <<EOF

${C_WARN}[중요]${C_OFF} 본 스크립트의 PATH 변경은 ${C_WARN}현재 셸에는 반영되지 않습니다${C_OFF}.
다음 중 하나로 즉시 적용하세요:

  ${C_OK}# 옵션 A — 현재 셸에 1회 적용${C_OFF}
  export PATH="$NPM_GLOBAL_PREFIX/bin:\$PATH"

  ${C_OK}# 옵션 B — rc 파일 다시 로드${C_OFF}
  source ~/.bashrc

확인:
  which claude            # $NPM_GLOBAL_PREFIX/bin/claude
  claude --version

EOF

log "다음 단계: bash scripts/oauth-tunnel.sh 로 OAuth 1회 인증"

#!/usr/bin/env bash
# USAGE: bash scripts/install-openclaw.sh [VERSION]
#
# OpenClaw (https://github.com/openclaw/openclaw) 자율 에이전트 설치.
#
# 인자:
#   VERSION   설치할 npm 패키지 버전 (기본: latest, 단 최소 핀 강제)
#
# 환경변수:
#   OPENCLAW_MIN_VERSION  최소 안전 버전 (기본 2026.2.6 — CVE-2026-25253 패치(2026.1.29)
#                         + VirusTotal 스캐너 포함 버전)
#   NPM_GLOBAL_PREFIX     사용자 글로벌 npm prefix (기본 ~/.npm-global)
#
# 본 스크립트는 OpenClaw 의 *런타임* 만 설치한다. 첫 페어링·채널 연결·BYOK 토큰
# 설정은 `openclaw onboard --install-daemon` 가 대화형으로 수행한다.

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

VERSION="${1:-latest}"
MIN_VERSION="${OPENCLAW_MIN_VERSION:-2026.2.6}"
NPM_GLOBAL_PREFIX="${NPM_GLOBAL_PREFIX:-$HOME/.npm-global}"

# ---------- 사전 점검 -------------------------------------------------------
command -v node >/dev/null 2>&1 || die "Node.js 가 없습니다. bootstrap-pi.sh 를 먼저 실행하세요."
command -v npm  >/dev/null 2>&1 || die "npm 이 없습니다. bootstrap-pi.sh 를 먼저 실행하세요."

NODE_MAJOR="$(node --version | sed -E 's/^v([0-9]+).*/\1/')"
if [[ "$NODE_MAJOR" -lt 22 ]]; then
    die "Node $NODE_MAJOR 감지. OpenClaw 는 Node 22.16+ (권장 24) 가 필요합니다. bootstrap-pi.sh 의 NODE_MAJOR 를 22 또는 24 로 올리고 재실행하세요."
fi
ok "Node $(node --version) 감지 (≥ 22 요구 충족)"

# 글로벌 prefix 사용자 홈으로
mkdir -p "$NPM_GLOBAL_PREFIX/bin"
npm config set prefix "$NPM_GLOBAL_PREFIX"
export PATH="$NPM_GLOBAL_PREFIX/bin:$PATH"

# ---------- 설치 -----------------------------------------------------------
log "@openclaw/cli (또는 openclaw) 설치 시작 (version=$VERSION, prefix=$NPM_GLOBAL_PREFIX)..."

# OpenClaw 의 npm 패키지명은 'openclaw' (https://github.com/openclaw/openclaw 의 README 기준)
# 변경 시 OPENCLAW_NPM_PKG 환경변수로 오버라이드 가능.
PKG="${OPENCLAW_NPM_PKG:-openclaw}"

npm install -g "${PKG}@${VERSION}" || die "npm install 실패. 네트워크 / 디스크 / npm prefix 권한을 점검하세요."

# ---------- 설치 검증 + 최소 버전 ------------------------------------------
if ! command -v openclaw >/dev/null 2>&1; then
    warn "openclaw 바이너리를 PATH 에서 찾지 못했습니다. 현재 셸에 PATH 를 적용하세요:"
    warn "  export PATH=\"$NPM_GLOBAL_PREFIX/bin:\$PATH\""
    die  "PATH 적용 후 'openclaw --version' 으로 확인 후 다음 단계로."
fi

INSTALLED_VERSION="$(openclaw --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo unknown)"
ok "설치 완료: openclaw $INSTALLED_VERSION"

# 최소 버전 비교 (sort -V) — INSTALLED < MIN 이면 경고
if [[ "$INSTALLED_VERSION" != "unknown" ]]; then
    OLDEST="$(printf '%s\n%s\n' "$INSTALLED_VERSION" "$MIN_VERSION" | sort -V | head -1)"
    if [[ "$OLDEST" != "$MIN_VERSION" ]]; then
        warn "설치된 버전 ($INSTALLED_VERSION) 이 최소 권장 ($MIN_VERSION) 미만입니다."
        warn "CVE-2026-25253 (CVSS 8.8) 패치가 누락된 버전일 수 있습니다 — docs/07-openclaw-hardening.md 참고."
        warn "  → npm install -g openclaw@latest 로 갱신 권장."
    fi
fi

# ---------- 다음 단계 안내 --------------------------------------------------
cat <<EOF

${C_INFO}========================================================================${C_OFF}
${C_INFO} 다음 단계${C_OFF}
${C_INFO}========================================================================${C_OFF}

1) 대화형 온보딩 (BYOK 토큰 / 페어링 / 채널 연결):

     ${C_OK}openclaw onboard --install-daemon${C_OFF}

   설정 파일 위치: ~/.openclaw/openclaw.json (JSON5)
   워크스페이스:    ~/.openclaw/workspace/
   스킬 디렉토리:   ~/.openclaw/skills/

2) Gateway 띄우기 (loopback 바인딩 권장 — 외부 노출 금지):

     ${C_OK}openclaw gateway --port 18789 --verbose${C_OFF}

3) 에이전트 호출:

     ${C_OK}openclaw agent --message "ship checklist" --thinking high${C_OFF}

${C_WARN}[보안 필독]${C_OFF} 외부 reverse proxy 뒤에 두려면 docs/07-openclaw-hardening.md 의
gateway.trustedProxies / gateway.bind 설정을 먼저 적용하세요. 공개 노출 인스턴스의
~93.4% 가 인증 우회에 노출 (CVE-2026-25253 + 인증 우회 이슈).

EOF
log "install-openclaw.sh 끝."

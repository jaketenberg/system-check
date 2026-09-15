#!/bin/sh
#
# check-prereqs.sh — pre-interview environment checker
#
# Verifies that a candidate's machine has the tools needed for the
# interview. Run it before the interview:
#
#   sh check-prereqs.sh
#
# Flags:
#   --help            Show this help
#
# Exit code: 0 = ready, 1 = one or more required checks failed.

set -u

print_usage() {
  awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "$0"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)   print_usage; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)"; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# Output helpers (colors degrade gracefully when not on a TTY)
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  C_GREEN='\033[32m'; C_RED='\033[31m'; C_YELLOW='\033[33m'
  C_BLUE='\033[34m'; C_DIM='\033[2m'; C_BOLD='\033[1m'; C_OFF='\033[0m'
else
  C_GREEN=''; C_RED=''; C_YELLOW=''; C_BLUE=''; C_DIM=''; C_BOLD=''; C_OFF=''
fi

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT+1)); printf "  ${C_GREEN}✔ PASS${C_OFF}  %s\n" "$1"; }
warn() { WARN_COUNT=$((WARN_COUNT+1)); printf "  ${C_YELLOW}▲ WARN${C_OFF}  %s\n" "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT+1)); printf "  ${C_RED}✘ FAIL${C_OFF}  %s\n" "$1"; }

section() {
  printf "\n${C_BOLD}${C_BLUE}%s${C_OFF}\n" "$1"
}

guidance() {
  # Print indented install/config guidance, preserving line breaks
  printf "${C_DIM}%s${C_OFF}\n" "$1" | sed 's/^/          /'
}

have() { command -v "$1" >/dev/null 2>&1; }

# Detect OS for platform-specific guidance
OS="$(uname -s)"
case "$OS" in
  Darwin)  OS_NAME="macOS" ;;
  Linux)   OS_NAME="Linux" ;;
  *)       OS_NAME="$OS" ;;
esac

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

section "1. Java 21"

check_java() {
  if ! have java; then
    fail "java not found on PATH"
    guidance "Install a JDK 21:"
    if [ "$OS_NAME" = "macOS" ]; then
      guidance "  macOS:  brew install --cask temurin@21"
    else
      guidance "  Linux:  sudo apt install openjdk-21-jdk   (Debian/Ubuntu)"
      guidance "          sudo dnf install java-21-openjdk  (Fedora/RHEL)"
    fi
    guidance "  Any platform: https://adoptium.net/temurin/releases/?version=21"
    guidance "  Or with SDKMAN:  curl -s https://get.sdkman.io | sh && sdk install java 21.0.9-tem"
    return
  fi

  JAVA_VERSION_LINE="$(java -version 2>&1 | head -1)"
  JAVA_MAJOR="$(printf '%s' "$JAVA_VERSION_LINE" \
    | sed -E 's/.*version "([0-9]+).*/\1/')"

  if ! printf '%s' "$JAVA_MAJOR" | grep -Eq '^[0-9]+$'; then
    fail "Could not parse Java version from: $JAVA_VERSION_LINE"
    guidance "Make sure 'java -version' works and reports a 21.x JDK."
    return
  fi

  if [ "$JAVA_MAJOR" -lt 21 ]; then
    fail "Found Java $JAVA_MAJOR, but Java 21 is required (found: $JAVA_VERSION_LINE)"
    guidance "  The project compiles with target 21 (see pom.xml)."
    if [ "$OS_NAME" = "macOS" ]; then
      guidance "  macOS:  brew install --cask temurin@21"
    else
      guidance "  Linux:  sudo apt install openjdk-21-jdk   (Debian/Ubuntu)"
      guidance "          sudo dnf install java-21-openjdk  (Fedora/RHEL)"
    fi
    guidance "  Or with SDKMAN:  sdk install java 21.0.9-tem"
    guidance "  If multiple JDKs are installed, point JAVA_HOME at the 21 JDK."
    return
  fi

  if [ "$JAVA_MAJOR" -gt 21 ]; then
    warn "Found Java $JAVA_MAJOR — the project targets Java 21. A 21.x JDK is recommended."
    guidance "  Install 21 and set JAVA_HOME, e.g. (macOS):"
    guidance "    brew install --cask temurin@21"
    guidance "    export JAVA_HOME=\$(/usr/libexec/java_home -v 21)"
  else
    pass "Java 21 found: $JAVA_VERSION_LINE"
  fi

  if ! have javac; then
    fail "javac not found — you appear to have a JRE, not a full JDK"
    guidance "Building with Maven requires the JDK compiler (javac)."
    guidance "Install the full JDK 21 (see links above) and make sure it is on PATH."
  else
    pass "javac (JDK compiler) found"
  fi
}
check_java

# ---------------------------------------------------------------------------

section "2. Docker"

check_docker_cli() {
  if ! have docker; then
    fail "docker not found on PATH"
    if [ "$OS_NAME" = "macOS" ]; then
      guidance "  macOS: install Docker Desktop — https://docs.docker.com/desktop/setup/install/mac-install/"
      guidance "  or: brew install --cask docker"
    else
      guidance "  Linux: https://docs.docker.com/engine/install/ (follow your distro's instructions)"
    fi
    return
  fi
  DOCKER_VERSION="$(docker --version 2>/dev/null || echo '?')"
  pass "docker CLI found: $DOCKER_VERSION"
}
check_docker_cli

check_docker_daemon() {
  if ! have docker; then
    return  # already failed above
  fi
  if docker info >/dev/null 2>&1; then
    pass "Docker daemon is running"
  else
    fail "Docker is installed but the daemon is not reachable"
    if [ "$OS_NAME" = "macOS" ]; then
      guidance "  Start Docker Desktop from Applications, then wait for it to finish starting."
    else
      guidance "  Linux: sudo systemctl start docker"
      guidance "  If you get permission errors, add yourself to the docker group:"
      guidance "    sudo usermod -aG docker \$USER   (then log out and back in)"
    fi
  fi
}
check_docker_daemon

# ---------------------------------------------------------------------------

section "3. Claude Code CLI (AI coding assistant)"

check_claude() {
  if ! have claude; then
    fail "claude (Claude Code CLI) not found on PATH"
    guidance "Install Claude Code:"
    guidance "  npm install -g @anthropic-ai/claude-code"
    guidance "  or the native installer: curl -fsSL https://claude.ai/install.sh | bash"
    guidance "Then start it once with 'claude' to confirm it launches."
    return
  fi
  CLAUDE_VERSION="$(claude --version 2>/dev/null || echo '?')"
  pass "Claude Code CLI found: $CLAUDE_VERSION"
}
check_claude

# ---------------------------------------------------------------------------

section "4. Supporting tools and network access"

check_git() {
  if have git; then
    pass "git found: $(git --version)"
  else
    warn "git not found — you will need it to clone the interview repo"
    if [ "$OS_NAME" = "macOS" ]; then
      guidance "  macOS: xcode-select --install  (includes git)"
    else
      guidance "  Linux: sudo apt install git   (Debian/Ubuntu)"
      guidance "         sudo dnf install git   (Fedora/RHEL)"
    fi
  fi
}
check_git

check_network() {
  if ! have curl; then
    warn "curl not found — cannot verify network reachability"
    guidance "  This script uses curl to test that Maven Central"
    guidance "  are reachable. Install it, or verify manually in a browser:"
    if [ "$OS_NAME" = "macOS" ]; then
      guidance "  macOS:  curl is preinstalled; if missing, reinstall Command Line Tools: xcode-select --install"
    else
      guidance "  Linux:  sudo apt install curl   (Debian/Ubuntu)"
      guidance "          sudo dnf install curl   (Fedora/RHEL)"
    fi
    guidance "  Then re-run this script."
    return
  fi
  for target in repo.maven.apache.org; do
    CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$target/" 2>/dev/null)"
    if [ -n "$CODE" ] && [ "$CODE" != "000" ]; then
      pass "Network: reachable https://$target/ (HTTP $CODE)"
    else
      fail "Network: cannot reach https://$target/"
      guidance "  Maven builds and Claude Code both need outbound HTTPS."
      guidance "  If you are behind a corporate proxy, configure it for git/curl/Maven"
      guidance "  (e.g. MAVEN_OPTS / ~/.m2/settings.xml proxy, HTTPS_PROXY env var)."
    fi
  done
}
check_network

# ---------------------------------------------------------------------------

printf "\n${C_BOLD}──────────────────── Summary ────────────────────${C_OFF}\n"
printf "  ${C_GREEN}✔ %d passed${C_OFF}   ${C_YELLOW}▲ %d warnings${C_OFF}   ${C_RED}✘ %d failed${C_OFF}\n" \
  "$PASS_COUNT" "$WARN_COUNT" "$FAIL_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
  printf "\n${C_BOLD}${C_RED}NOT READY${C_OFF} — fix the FAIL items above, then re-run this script.\n"
  exit 1
elif [ "$WARN_COUNT" -gt 0 ]; then
  printf "\n${C_BOLD}${C_YELLOW}MOSTLY READY${C_OFF} — review the WARN items above before the interview.\n"
  exit 0
else
  printf "\n${C_BOLD}${C_GREEN}ALL CHECKS PASSED${C_OFF} — you're ready for the interview.\n"
  exit 0
fi

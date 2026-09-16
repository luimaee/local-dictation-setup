#!/usr/bin/env bash
#
# Installs Handy (local speech-to-text) on macOS.
#
# Detects your chip, picks the matching build, and tells you which model to use
# and why. Also explains the Sotto situation if you landed here from that repo.
#
# Usage:  ./install-handy-macos.sh

set -euo pipefail

HANDY_VERSION="0.9.6"
BASE_URL="https://github.com/cjpais/Handy/releases/download/v${HANDY_VERSION}"

step() { printf '\n==> %s\n' "$1"; }
ok()   { printf '    %s\n' "$1"; }
warn() { printf '    %s\n' "$1" >&2; }

step "Detecting hardware"

ARCH="$(uname -m)"
MACOS_VERSION="$(sw_vers -productVersion)"
CHIP="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"

ok "macOS ${MACOS_VERSION}"
ok "Arch: ${ARCH}"
ok "Chip: ${CHIP}"

case "$ARCH" in
  arm64)
    DMG="Handy_${HANDY_VERSION}_aarch64.dmg"
    APPLE_SILICON=1
    ;;
  x86_64)
    DMG="Handy_${HANDY_VERSION}_x64.dmg"
    APPLE_SILICON=0
    warn ""
    warn "Intel Mac detected."
    warn "If you came here looking at Sotto: it will not run on this machine."
    warn "Sotto requires the Apple Neural Engine, which Intel Macs don't have."
    warn "There is no CPU fallback. Handy is the working alternative."
    warn ""
    ;;
  *)
    echo "Unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac

step "Installing Handy"

if command -v brew >/dev/null 2>&1; then
  ok "Homebrew found - installing cask (picks the right arch automatically)."
  brew install --cask handy
else
  ok "No Homebrew. Downloading ${DMG}."

  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  curl -fL --progress-bar -o "${TMP}/${DMG}" "${BASE_URL}/${DMG}"

  ok "Mounting."
  MOUNT_POINT="$(hdiutil attach "${TMP}/${DMG}" -nobrowse -readonly |
                 grep -o '/Volumes/.*' | head -1)"

  ok "Copying to /Applications."
  rm -rf "/Applications/Handy.app"
  cp -R "${MOUNT_POINT}/Handy.app" /Applications/

  hdiutil detach "$MOUNT_POINT" -quiet
  ok "Installed."
fi

step "Clearing quarantine"

# Stops the "Handy is damaged and can't be opened" Gatekeeper message.
xattr -cr /Applications/Handy.app 2>/dev/null || true
ok "Done."

step "Launching"
open -a Handy
ok "Handy is starting - it lives in your menu bar."

step "What to do next"

cat <<'EOF'
    1. PERMISSIONS - two prompts, both required:

         Microphone     - prompted on first launch.
         Accessibility  - System Settings > Privacy & Security > Accessibility,
                          toggle Handy on.

       Skipping Accessibility is the #1 reason people think Handy is broken.
       It will record and transcribe perfectly, then paste nothing at all.

    2. MODEL - pick one in the Handy window.
EOF

if [ "$APPLE_SILICON" -eq 1 ]; then
  cat <<'EOF'
         Apple Silicon: Cohere Transcribe (1.6 GB) if you want best accuracy,
         or Parakeet Unified EN 0.6B (697 MB) if you want it snappier.
EOF
else
  cat <<'EOF'
         Intel Mac: Parakeet Unified EN 0.6B (697 MB). You have no Neural
         Engine and likely no usable GPU backend, so everything runs on the
         CPU. Do NOT pick Cohere Transcribe or Whisper Medium/Large - they
         will be painfully slow. If you want Whisper, take Small.

         Expect a real pause after you stop speaking - seconds, not
         milliseconds, scaling with how long you talked. Short bursts feel
         fine; long paragraphs make you wait.
EOF
fi

cat <<'EOF'

    3. HOTKEY - the macOS default is Option+Space. Change it in Settings if
       that collides with anything you use.

    4. VERIFY THE BACKEND - check ~/Library/Logs/com.pais.handy/ for a line
       reading "bound backend '...'". That tells you what's actually doing
       the work rather than what you hoped would.

    Test it: click into any text field, hold the hotkey, talk, let go.

EOF

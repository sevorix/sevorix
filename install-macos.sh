#!/usr/bin/env bash
#
# Sevorix Pro installer — macOS (Apple Silicon).
#
#   curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/install-macos.sh | bash
#
# Downloads the latest Sevorix Pro release from github.com/sevorix/sevorix,
# verifies its SHA-256, extracts the aarch64-macos bundle, and hands off to the
# bundle's own install-binary-macos.sh — which is the script that actually
# installs anything.
#
# This file is fetched and piped to a shell, so it deliberately does as little
# as possible: fetch, verify, hand off. It installs nothing itself and never
# calls sudo. It is the macOS counterpart of install.sh (Linux), kept as a
# separate file so that each one-liner runs exactly one platform's code path;
# the two are structurally parallel so they can be reviewed side by side.
#
# It must run under the /bin/bash macOS ships, which is bash 3.2, against BSD
# userland: no arrays under `set -u`, no GNU-only flags, and `shasum -a 256`
# rather than `sha256sum`.
#
# CANONICAL SOURCE: public/sevorix-repo/install-macos.sh in
# sevorix/sevorix-watchtower. Edit it there; this file is a hand-applied copy
# (see that directory's NOTES.md). SEVORIX_MACOS_INSTALLER_VERSION below
# identifies which copy a machine actually ran. It is independent of
# install.sh's SEVORIX_INSTALLER_VERSION: the files drift separately.

set -euo pipefail

SEVORIX_MACOS_INSTALLER_VERSION="1"

# Overridable for internal mirrors and for the test harness — the same names
# install.sh uses. Both are announced when set: this script chooses where a
# binary comes from, so a non-default source must never be a silent one.
# Neither is a privilege boundary — anything able to set them is already inside
# the shell this script runs in.
REPO="${SEVORIX_INSTALL_REPO:-sevorix/sevorix}"
API="${SEVORIX_INSTALL_API:-https://api.github.com}"

VERSION="${SEVORIX_VERSION:-latest}"
ASSUME_YES=0
DRY_RUN=0

fail() { printf '\n❌ %s\n' "$1" >&2; shift; for line in "$@"; do printf '   %s\n' "$line" >&2; done; exit 1; }
say()  { printf '%s\n' "$1"; }

usage() {
    cat <<'EOF'
Sevorix Pro installer — macOS (Apple Silicon)

Usage:
  curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/install-macos.sh | bash
  curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/install-macos.sh | bash -s -- --yes

Options:
  --version X.Y.Z   Install a specific release (default: the latest published
                    release). macOS builds are published from 1.0.2 onwards.
  --yes             Accept every prompt without asking. Required for
                    unattended installs.
  --dry-run         Resolve the release and print what would happen. Downloads
                    nothing, installs nothing.
  --help            Show this message.

Environment:
  SEVORIX_VERSION        Same as --version.
  SEVORIX_INSTALL_REPO   Release repository (default: sevorix/sevorix).
  SEVORIX_INSTALL_API    GitHub API base URL (default: https://api.github.com).

What this installs, and what it will ask you:
  The release bundle's install-binary-macos.sh places sevorix and sevsh in
  ~/.local/bin and creates ~/.sevorix and ~/.local/state/sevorix. It asks
  before pulling the default policies and roles from Sevorix Hub, and before
  the one step that uses sudo: adding Sevorix's TLS interception CA to the
  System Keychain, offered only once you have enabled TLS inspection and a CA
  exists. (The 1.0.2 bundle runs that step without asking.) --yes accepts all
  of them.

  On macOS, eBPF syscall monitoring, seccomp syscall interception, session
  containment and the agent integrations are not available: they are Linux
  kernel features. The HTTP proxy, policy engine, sevsh and the Observatory
  dashboard are.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version) [ $# -ge 2 ] || fail "--version needs a value (e.g. --version 1.0.2)"; VERSION="$2"; shift 2 ;;
        --version=*) VERSION="${1#*=}"; shift ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) fail "Unknown option: $1" "Run with --help for usage." ;;
    esac
done

say "--------------------------------------------------"
say "🛡️  Sevorix Pro installer (macOS)"
say "--------------------------------------------------"

# ---------------------------------------------------------------
# Refuse to run as root.
#
# install-binary-macos.sh installs into $HOME/.local/bin and $HOME/.sevorix.
# Under `sudo bash` that is root's home — a working install for nobody, and
# root-owned files in the paths the real user's daemon later needs to write.
# ---------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
    fail "Do not run this installer as root." \
         "It installs Sevorix for a specific user account and only uses sudo itself" \
         "for the one step that needs it. Re-run it as your normal user:" \
         "" \
         "  curl -fsSL https://raw.githubusercontent.com/$REPO/main/install-macos.sh | bash"
fi

# ---------------------------------------------------------------
# Platform check — only darwin/arm64 is published for macOS.
#
# Done before any network access, so an unsupported machine is told so
# immediately rather than after a 20+ MB download.
#
# A shell running under Rosetta on an Apple Silicon Mac reports x86_64, so
# `uname -m` alone would call that Mac "Intel" and send its owner to the wrong
# product. hw.optional.arm64 reports the hardware, not the process, so it tells
# the two apart.
# ---------------------------------------------------------------
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS/$ARCH" in
    Darwin/arm64)
        ;;
    Darwin/x86_64)
        if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = "1" ]; then
            fail "This shell is running under Rosetta (it reports x86_64 on an Apple Silicon Mac)." \
                 "Sevorix Pro for macOS is a native arm64 build. Re-run the installer" \
                 "from a native terminal — check with \`uname -m\`, which should print arm64:" \
                 "" \
                 "  curl -fsSL https://raw.githubusercontent.com/$REPO/main/install-macos.sh | bash"
        fi
        fail "Sevorix Pro supports Apple Silicon Macs only (found: $OS $ARCH)." \
             "Intel Macs are not supported." \
             "" \
             "The open-source Sevorix Lite edition builds from source on Intel Macs:" \
             "  https://github.com/sevorix/sevorix-lite"
        ;;
    Linux/*)
        fail "This is the macOS installer (found: $OS $ARCH)." \
             "On Linux x86_64 (including WSL2), use install.sh:" \
             "" \
             "  curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash"
        ;;
    *)
        fail "Sevorix Pro is published for Apple Silicon macOS and Linux x86_64 only (found: $OS $ARCH)." \
             "" \
             "The open-source Sevorix Lite edition builds from source:" \
             "  https://github.com/sevorix/sevorix-lite"
        ;;
esac

# macOS ships `shasum` (Perl) on every release; `sha256sum` only on some. The
# fallback keeps this script runnable wherever only coreutils exists (the
# Linux test container) without making either one a hard requirement.
if command -v shasum > /dev/null 2>&1; then
    sha256() { shasum -a 256 "$@"; }
    SHA_DESC="shasum -a 256 -c"
elif command -v sha256sum > /dev/null 2>&1; then
    sha256() { sha256sum "$@"; }
    SHA_DESC="sha256sum -c"
else
    fail "'shasum' is required but not installed." \
         "It ships with macOS; if it is missing, the system Perl installation is damaged."
fi

for dep in curl tar; do
    command -v "$dep" > /dev/null 2>&1 || fail "'$dep' is required but not installed."
done
if ! command -v sudo > /dev/null 2>&1; then
    say "⚠️  'sudo' not found. Trusting the TLS interception CA will not be possible;"
    say "   everything else will still install."
fi

if [ "$REPO" != "sevorix/sevorix" ] || [ "$API" != "https://api.github.com" ]; then
    say ""
    say "⚠️  Using a non-default release source:"
    say "      repository: $REPO"
    say "      API base:   $API"
fi

# ---------------------------------------------------------------
# Resolve the release.
#
# The asset names are read from the release rather than constructed, for the
# reason install.sh gives: they have changed before, and an installer that
# guesses the filename breaks silently and remotely the next time they do.
# ---------------------------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ "$VERSION" = "latest" ]; then
    RELEASE_URL="$API/repos/$REPO/releases/latest"
else
    RELEASE_URL="$API/repos/$REPO/releases/tags/$VERSION"
fi

say ""
say "==> Resolving release ($VERSION) from $REPO"

# `|| true` because a 404 is a case handled below with a real explanation, not
# a reason to die with curl's exit code. A non-HTTP transport (file://, used by
# the test harness and by mirrors) reports code 000, so an empty-but-present
# body is judged by content rather than status.
HTTP_CODE="$(curl -sSL -o "$WORK/release.json" -w '%{http_code}' "$RELEASE_URL" 2>/dev/null || true)"

if ! grep -q '"tag_name"' "$WORK/release.json" 2>/dev/null; then
    if [ "$HTTP_CODE" = "404" ] && [ "$VERSION" != "latest" ]; then
        fail "No release tagged '$VERSION' was found in $REPO." \
             "List the available releases at https://github.com/$REPO/releases"
    fi
    if [ "$HTTP_CODE" = "404" ]; then
        fail "No published release found for $REPO." \
             "The repository exists but has no releases yet, so there is nothing" \
             "to install. See https://github.com/$REPO/releases"
    fi
    fail "Could not read release metadata from $RELEASE_URL (HTTP $HTTP_CODE)." \
         "Check your network connection and try again."
fi

# `${var%%$'\n'*}` rather than `| head -1` throughout this section: under
# `set -o pipefail`, head closing the pipe early kills the producer with
# SIGPIPE and fails the pipeline — see the matching comment in install.sh.
TAG="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$WORK/release.json")"
TAG="${TAG%%$'\n'*}"
[ -n "$TAG" ] || fail "Could not determine the release tag from $RELEASE_URL."

# Every asset download URL, one per line, then picked apart by suffix.
ASSETS="$(sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$WORK/release.json")"
#
# Matched on both `macos` and `aarch64` rather than on a full filename, the
# same way install.sh matches `linux` and `x86_64`: a reordering of the two
# still matches, and the Linux asset in the same release never can.
TARBALL_URL="$(printf '%s\n' "$ASSETS" | grep -E '\.tar\.gz$' | grep 'macos' | grep 'aarch64' || true)"
CHECKSUM_URL="$(printf '%s\n' "$ASSETS" | grep -E '\.tar\.gz\.sha256$' | grep 'macos' | grep 'aarch64' || true)"
TARBALL_URL="${TARBALL_URL%%$'\n'*}"
CHECKSUM_URL="${CHECKSUM_URL%%$'\n'*}"

[ -n "$TARBALL_URL" ] || fail "Release $TAG has no macOS (Apple Silicon) .tar.gz asset." \
    "macOS builds are published from release 1.0.2 onwards; an older --version" \
    "has no macOS build to install." \
    "Assets found:" "$(printf '%s\n' "$ASSETS" | sed 's/^/  /')"
[ -n "$CHECKSUM_URL" ] || fail "Release $TAG has no .tar.gz.sha256 asset for the macOS archive." \
    "Refusing to install an archive whose checksum cannot be verified."

TARBALL_NAME="$(basename "$TARBALL_URL")"

say "    Release:  $TAG"
say "    Archive:  $TARBALL_NAME"

if [ "$DRY_RUN" -eq 1 ]; then
    say ""
    say "Dry run — nothing was downloaded or installed."
    say "  Would download: $TARBALL_URL"
    say "                  $CHECKSUM_URL"
    say "  Would verify:   $SHA_DESC $TARBALL_NAME.sha256"
    if [ "$ASSUME_YES" -eq 1 ]; then
        say "  Would run:      ./install-binary-macos.sh --force"
    else
        say "  Would run:      ./install-binary-macos.sh  (prompting on /dev/tty)"
    fi
    exit 0
fi

# ---------------------------------------------------------------
# Download and verify.
#
# No quarantine handling is needed, deliberately: com.apple.quarantine is set
# by browsers and other LSQuarantine-aware apps, not by curl, so nothing
# downloaded here carries it. Do not add an `xattr -d` step "to be safe" — it
# would be a no-op today and a Gatekeeper bypass in waiting.
# ---------------------------------------------------------------
say ""
say "==> Downloading $TARBALL_NAME"
curl -fsSL -o "$WORK/$TARBALL_NAME" "$TARBALL_URL" \
    || fail "Download failed: $TARBALL_URL"
curl -fsSL -o "$WORK/$TARBALL_NAME.sha256" "$CHECKSUM_URL" \
    || fail "Download failed: $CHECKSUM_URL"

say "==> Verifying SHA-256"
# Normalised to name exactly the archive just downloaded, as in install.sh:
# published .sha256 files have carried a bare hash and a path-qualified name at
# different times, and `-c` fails on both for reasons unrelated to the bytes.
EXPECTED="$(awk '{print $1; exit}' "$WORK/$TARBALL_NAME.sha256")"
[ -n "$EXPECTED" ] || fail "Checksum file $TARBALL_NAME.sha256 is empty or unreadable."
printf '%s  %s\n' "$EXPECTED" "$TARBALL_NAME" > "$WORK/$TARBALL_NAME.sha256.check"

if ! ( cd "$WORK" && sha256 -c "$TARBALL_NAME.sha256.check" > /dev/null 2>&1 ); then
    fail "SHA-256 mismatch for $TARBALL_NAME." \
         "Expected: $EXPECTED" \
         "Actual:   $(sha256 "$WORK/$TARBALL_NAME" | cut -d' ' -f1)" \
         "" \
         "Nothing was installed. Do not use this download."
fi
say "    OK ($EXPECTED)"
say ""
say "    Note: this checksum was published alongside the archive, so it proves the"
say "    download is intact, not that the release is authentic. The same checksum"
say "    is printed in the release notes at"
say "    https://github.com/$REPO/releases/tag/$TAG — comparing against that is an"
say "    independent second source."

# ---------------------------------------------------------------
# Extract.
# ---------------------------------------------------------------
say ""
say "==> Extracting"
tar xzf "$WORK/$TARBALL_NAME" -C "$WORK" || fail "Could not extract $TARBALL_NAME."

BUNDLE_DIR="$(tar tzf "$WORK/$TARBALL_NAME")"
BUNDLE_DIR="${BUNDLE_DIR%%$'\n'*}"
BUNDLE_DIR="${BUNDLE_DIR%%/*}"
[ -n "$BUNDLE_DIR" ] && [ -d "$WORK/$BUNDLE_DIR" ] \
    || fail "Extracted archive does not contain the expected bundle directory."
[ -f "$WORK/$BUNDLE_DIR/install-binary-macos.sh" ] \
    || fail "Bundle $BUNDLE_DIR does not contain install-binary-macos.sh." \
            "This does not look like a Sevorix Pro macOS release bundle."
chmod +x "$WORK/$BUNDLE_DIR/install-binary-macos.sh" 2>/dev/null || true

# ---------------------------------------------------------------
# Hand off to the bundle's installer.
#
# Never let it inherit this script's stdin, for two reasons:
#
# * Under `curl … | bash`, bash reads this script from the pipe one line at a
#   time, and a child that inherits that stdin reads from the same pipe. The
#   bundle installer's first `read` would take the next line of THIS script as
#   the user's answer, and bash would then skip that line. Prompts answered by
#   script text, and a parent script missing a line, is not an outcome to
#   reason about — it is ruled out.
#
# * End-of-file is not a usable answer either way. Current bundles treat EOF
#   as "no", as install-binary.sh does on Linux, so a hand-off with nobody
#   there would decline every prompt and still exit 0. The 1.0.2 bundle treats
#   EOF as "yes", so the same hand-off would accept them all. Neither should
#   happen because nobody was there to answer.
#
# So the same three branches as install.sh: the real terminal when there is
# one; --force under an explicit --yes, with stdin pinned to /dev/null so even
# that path never touches the pipe; otherwise stop, having installed nothing.
#
# The terminal test opens /dev/tty rather than asking `test -r` about it, for
# the reason given in install.sh (the node can exist and be readable with no
# controlling terminal behind it).
#
# If a TLS interception CA already exists (TLS inspection enabled on an
# earlier install), the bundle runs `sudo security add-trusted-cert` — after a
# prompt in current bundles, unprompted in 1.0.2. sudo asks for a password on
# the terminal itself; under --yes with no terminal it cannot. Current bundles
# report that and carry on without HTTPS inspection; the 1.0.2 bundle fails
# the install there.
# ---------------------------------------------------------------
say ""
say "==> Running the bundle installer"
say ""

INSTALL_STATUS=0
if [ "$ASSUME_YES" -eq 1 ]; then
    ( cd "$WORK/$BUNDLE_DIR" && ./install-binary-macos.sh --force < /dev/null ) || INSTALL_STATUS=$?
elif ( : < /dev/tty ) 2>/dev/null; then
    ( cd "$WORK/$BUNDLE_DIR" && ./install-binary-macos.sh < /dev/tty ) || INSTALL_STATUS=$?
else
    fail "No terminal available to answer the installer's prompts." \
         "" \
         "Under a pipe with no terminal, the installer's prompts would read from" \
         "this script instead of from you — so it stops here instead." \
         "Nothing was installed." \
         "" \
         "To accept every prompt unattended:" \
         "" \
         "  curl -fsSL https://raw.githubusercontent.com/$REPO/main/install-macos.sh | bash -s -- --yes" \
         "" \
         "Or download and run it from a terminal:" \
         "" \
         "  curl -fsSL https://raw.githubusercontent.com/$REPO/main/install-macos.sh -o install-macos.sh" \
         "  bash install-macos.sh"
fi

if [ "$INSTALL_STATUS" -ne 0 ]; then
    fail "The bundle installer exited with status $INSTALL_STATUS." \
         "Scroll up for the step that failed. If it was adding the TLS interception" \
         "CA to the System Keychain, re-run this installer from a terminal so sudo" \
         "can ask for your password."
fi

# ---------------------------------------------------------------
# Next steps.
# ---------------------------------------------------------------
say ""
say "--------------------------------------------------"
say "Next steps"
say "--------------------------------------------------"
case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *)
        # zsh has been the default login shell since macOS 10.15.
        say ""
        say "  Add ~/.local/bin to your PATH (it is where sevorix was installed):"
        say "    echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
        say "    source ~/.zshrc"
        ;;
esac
say ""
say "  Sevorix Pro requires an active subscription. Sign in, then start the daemon:"
say ""
say "    sevorix hub login     # or: sevorix hub register"
say "    sevorix start"
say ""
say "  If sevsh refuses commands with \"No role configured for this session\","
say "  activate a role in ~/.sevorix/settings.json and restart the daemon:"
say "    { \"sevsh\": { \"default_role\": \"default\" } }"
say ""
say "  On macOS, the agent's other processes keep running while a flagged"
say "  (Yellow Lane) action waits for your review — they cannot be suspended."
say "  If flagged actions are blocked outright instead of held for review"
say "  (the 1.0.2 default), set in ~/.sevorix/settings.json:"
say "    { \"intervention\": { \"containment\": \"best_effort\" } }"
say ""
say "  Documentation and pricing: https://sevorix.com"
say ""

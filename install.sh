#!/usr/bin/env bash
#
# Sevorix Pro installer.
#
#   curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/install.sh | bash
#
# Downloads the latest Sevorix Pro release from github.com/sevorix/sevorix,
# verifies its SHA-256, extracts it, and hands off to the bundle's own
# install-binary.sh — which is the script that actually installs anything and
# the one that asks for every privileged step.
#
# This file is fetched and piped to a shell, so it deliberately does as little
# as possible: fetch, verify, hand off. It installs nothing itself and never
# calls sudo.
#
# CANONICAL SOURCE: public/sevorix-repo/install.sh in sevorix/sevorix-watchtower.
# Edit it there; this file is a hand-applied copy (see that directory's
# NOTES.md). SEVORIX_INSTALLER_VERSION below identifies which copy a machine
# actually ran.

set -euo pipefail

SEVORIX_INSTALLER_VERSION="1"

# Overridable for internal mirrors and for the test harness. Both are announced
# when set: this script chooses where a binary that will be granted passwordless
# root comes from, so a non-default source must never be a silent one. Neither
# is a privilege boundary — anything able to set them is already inside the
# shell this script runs in.
REPO="${SEVORIX_INSTALL_REPO:-sevorix/sevorix}"
API="${SEVORIX_INSTALL_API:-https://api.github.com}"

VERSION="${SEVORIX_VERSION:-latest}"
ASSUME_YES=0
DRY_RUN=0

fail() { printf '\n❌ %s\n' "$1" >&2; shift; for line in "$@"; do printf '   %s\n' "$line" >&2; done; exit 1; }
say()  { printf '%s\n' "$1"; }

usage() {
    cat <<'EOF'
Sevorix Pro installer

Usage:
  curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/install.sh | bash -s -- --yes

Options:
  --version X.Y.Z   Install a specific release (default: the latest published release)
  --yes             Accept every privileged step without prompting. Required for
                    unattended installs (CI, cloud-init, image builds).
  --dry-run         Resolve the release and print what would happen. Downloads
                    nothing, installs nothing.
  --help            Show this message.

Environment:
  SEVORIX_VERSION        Same as --version.
  SEVORIX_INSTALL_REPO   Release repository (default: sevorix/sevorix).
  SEVORIX_INSTALL_API    GitHub API base URL (default: https://api.github.com).

What this installs, and what it will ask you:
  The release bundle's install-binary.sh places sevorix in ~/.local/bin and
  privileged components in /usr/local/lib/sevorix and /usr/local/bin. It asks
  before each privileged step — passwordless sudoers rules, file capabilities
  on the eBPF daemon, and (later, if you enable TLS inspection) adding Sevorix's
  interception CA to the system trust store. --yes accepts all of them.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --version) [ $# -ge 2 ] || fail "--version needs a value (e.g. --version 1.0.0)"; VERSION="$2"; shift 2 ;;
        --version=*) VERSION="${1#*=}"; shift ;;
        --yes|-y) ASSUME_YES=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) fail "Unknown option: $1" "Run with --help for usage." ;;
    esac
done

say "--------------------------------------------------"
say "🛡️  Sevorix Pro installer"
say "--------------------------------------------------"

# ---------------------------------------------------------------
# Refuse to run as root.
#
# install-binary.sh installs the user-facing binary to $HOME/.local/bin and
# writes sudoers rules naming `id -un`. Under `sudo bash` that means installing
# into /root and granting root passwordless access to root — a working install
# for nobody. It calls sudo itself for the steps that need it.
# ---------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
    fail "Do not run this installer as root." \
         "It installs Sevorix for a specific user account and calls sudo itself" \
         "for the steps that need root. Re-run it as your normal user:" \
         "" \
         "  curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash"
fi

# ---------------------------------------------------------------
# Platform check — only linux/x86_64 is published.
# ---------------------------------------------------------------
OS="$(uname -s)"
ARCH="$(uname -m)"
if [ "$OS" != "Linux" ] || [ "$ARCH" != "x86_64" ]; then
    fail "Sevorix Pro is published for Linux x86_64 only (found: $OS $ARCH)." \
         "Linux on WSL2 is supported and reports as Linux x86_64." \
         "" \
         "For macOS, or for a non-x86_64 machine, the open-source Sevorix Lite" \
         "edition builds from source and ships darwin binaries:" \
         "  https://github.com/sevorix/sevorix-lite"
fi

for dep in curl tar sha256sum; do
    command -v "$dep" > /dev/null 2>&1 || fail "'$dep' is required but not installed."
done
if ! command -v sudo > /dev/null 2>&1; then
    say "⚠️  'sudo' not found. The privileged components (sevsh, the agent launcher,"
    say "   the eBPF daemon) cannot be installed without it; the rest will still work."
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
# The asset names are read from the release rather than constructed. They have
# already changed once (0.1.7 shipped as -linux-x86_64, the current packaging
# produces -x86_64-linux), and an installer that guesses the filename breaks
# silently and remotely the next time that happens.
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

# `${var%%$'\n'*}` rather than `| head -1` throughout this section. Under
# `set -o pipefail`, head exiting after the first line closes the pipe, the
# producer dies of SIGPIPE, and the whole pipeline reports failure — which
# `set -e` turns into a silent exit partway through an install. It survives
# only when the producer happens to finish first, so it fails on big inputs
# (a real release's JSON) and passes on small ones.
TAG="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$WORK/release.json")"
TAG="${TAG%%$'\n'*}"
[ -n "$TAG" ] || fail "Could not determine the release tag from $RELEASE_URL."

# Every asset download URL, one per line, then picked apart by suffix.
ASSETS="$(sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$WORK/release.json")"
#
# Matched on both `linux` and `x86_64` rather than on a full filename: the two
# orderings that have shipped (`-linux-x86_64`, `-x86_64-linux`) both satisfy
# this, and a release that later adds darwin or aarch64 assets cannot have one
# of them selected here by position.
TARBALL_URL="$(printf '%s\n' "$ASSETS" | grep -E '\.tar\.gz$' | grep 'linux' | grep 'x86_64' || true)"
CHECKSUM_URL="$(printf '%s\n' "$ASSETS" | grep -E '\.tar\.gz\.sha256$' | grep 'linux' | grep 'x86_64' || true)"
TARBALL_URL="${TARBALL_URL%%$'\n'*}"
CHECKSUM_URL="${CHECKSUM_URL%%$'\n'*}"

[ -n "$TARBALL_URL" ] || fail "Release $TAG has no Linux x86_64 .tar.gz asset." \
    "Assets found:" "$(printf '%s\n' "$ASSETS" | sed 's/^/  /')"
[ -n "$CHECKSUM_URL" ] || fail "Release $TAG has no .tar.gz.sha256 asset for the Linux archive." \
    "Refusing to install an archive whose checksum cannot be verified."

TARBALL_NAME="$(basename "$TARBALL_URL")"

say "    Release:  $TAG"
say "    Archive:  $TARBALL_NAME"

if [ "$DRY_RUN" -eq 1 ]; then
    say ""
    say "Dry run — nothing was downloaded or installed."
    say "  Would download: $TARBALL_URL"
    say "                  $CHECKSUM_URL"
    say "  Would verify:   sha256sum -c $TARBALL_NAME.sha256"
    if [ "$ASSUME_YES" -eq 1 ]; then
        say "  Would run:      ./install-binary.sh --force"
    else
        say "  Would run:      ./install-binary.sh  (prompting on /dev/tty)"
    fi
    exit 0
fi

# ---------------------------------------------------------------
# Download and verify.
# ---------------------------------------------------------------
say ""
say "==> Downloading $TARBALL_NAME"
curl -fsSL -o "$WORK/$TARBALL_NAME" "$TARBALL_URL" \
    || fail "Download failed: $TARBALL_URL"
curl -fsSL -o "$WORK/$TARBALL_NAME.sha256" "$CHECKSUM_URL" \
    || fail "Download failed: $CHECKSUM_URL"

say "==> Verifying SHA-256"
# The checksum file is normalised to name exactly the archive just downloaded:
# published .sha256 files have carried a bare hash and a path-qualified name at
# different times, and `sha256sum -c` fails on both for reasons that have
# nothing to do with the bytes being wrong.
EXPECTED="$(awk '{print $1; exit}' "$WORK/$TARBALL_NAME.sha256")"
[ -n "$EXPECTED" ] || fail "Checksum file $TARBALL_NAME.sha256 is empty or unreadable."
printf '%s  %s\n' "$EXPECTED" "$TARBALL_NAME" > "$WORK/$TARBALL_NAME.sha256.check"

if ! ( cd "$WORK" && sha256sum -c "$TARBALL_NAME.sha256.check" > /dev/null 2>&1 ); then
    fail "SHA-256 mismatch for $TARBALL_NAME." \
         "Expected: $EXPECTED" \
         "Actual:   $(sha256sum "$WORK/$TARBALL_NAME" | cut -d' ' -f1)" \
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
[ -f "$WORK/$BUNDLE_DIR/install-binary.sh" ] \
    || fail "Bundle $BUNDLE_DIR does not contain install-binary.sh." \
            "This does not look like a Sevorix Pro release bundle."
chmod +x "$WORK/$BUNDLE_DIR/install-binary.sh" 2>/dev/null || true

# ---------------------------------------------------------------
# Hand off to the bundle's installer.
#
# The hard part. install-binary.sh asks before every privileged step — sudoers
# rules granting passwordless root, setcap on the eBPF daemon, adding a TLS
# interception CA to the system trust store — and, since the audit that fixed
# it, treats end-of-file on stdin as "no" rather than "yes".
#
# Under `curl … | bash`, stdin IS this script. Every one of those prompts would
# hit EOF and be declined, and the install would exit 0 having placed a sevorix
# binary in ~/.local/bin and nothing else: the CLI present, the enforcement
# boundary absent, and the reason scrolled past in "skipped" lines. That is the
# single worst outcome available here, so it is the one case ruled out.
#
# So: run the installer against the real terminal when there is one, so a piped
# install still gets genuine prompts. Without a terminal, require --yes — an
# explicit statement that nobody is there and every privileged step is accepted
# — and otherwise stop, having installed nothing.
# ---------------------------------------------------------------
say ""
say "==> Running the bundle installer"
say ""

#
# The terminal test opens /dev/tty rather than asking `test -r` about it. The
# device node exists and is world-readable in a container or CI job with no
# controlling terminal, so `test -r` says yes and the open then fails with
# ENXIO — which would turn the one case this logic exists for into a confusing
# redirection error instead of the explanation below.
INSTALL_STATUS=0
if [ "$ASSUME_YES" -eq 1 ]; then
    ( cd "$WORK/$BUNDLE_DIR" && ./install-binary.sh --force ) || INSTALL_STATUS=$?
elif ( : < /dev/tty ) 2>/dev/null; then
    ( cd "$WORK/$BUNDLE_DIR" && ./install-binary.sh < /dev/tty ) || INSTALL_STATUS=$?
else
    fail "No terminal available to confirm the privileged install steps." \
         "" \
         "Sevorix's installer asks before granting passwordless sudo, applying file" \
         "capabilities, and trusting a TLS interception CA. With no terminal it would" \
         "decline all of them and leave you with the CLI and no enforcement — so it" \
         "stops here instead. Nothing was installed." \
         "" \
         "To accept every privileged step unattended (CI, cloud-init, image builds):" \
         "" \
         "  curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh | bash -s -- --yes" \
         "" \
         "Or download and run it from a terminal:" \
         "" \
         "  curl -fsSL https://raw.githubusercontent.com/$REPO/main/install.sh -o install.sh" \
         "  bash install.sh"
fi

if [ "$INSTALL_STATUS" -ne 0 ]; then
    fail "The bundle installer exited with status $INSTALL_STATUS." \
         "Scroll up for the step that failed."
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
        say ""
        say "  Add ~/.local/bin to your PATH (it is where sevorix was installed):"
        say "    echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.bashrc"
        say "    source ~/.bashrc"
        ;;
esac
say ""
say "  Sevorix Pro requires an active subscription. Sign in, then start the daemon:"
say ""
say "    sevorix hub login     # or: sevorix hub register"
say "    sevorix start"
say ""
say "  Documentation and pricing: https://sevorix.com"
say ""

#!/usr/bin/env bash
#
# Sevorix Pro uninstaller.
#
#   curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/uninstall.sh | bash
#
# Removes what install.sh (via the bundle's install-binary.sh) put on this
# machine: the passwordless sudoers rules, the root-owned privileged binaries,
# the trusted TLS interception CA, the userns sysctl drop-in, and the sevorix
# binary itself. Your own configuration in ~/.sevorix — policies, roles,
# settings, hooks, logs, credentials — is left in place unless you pass --purge.
#
# Unlike install.sh this script calls sudo itself: there is no release bundle
# to hand off to. It lists everything it will do, asks once, and then reports
# what it removed, what it deliberately left, and what it could not remove.
#
# CANONICAL SOURCE: public/sevorix-repo/uninstall.sh in sevorix/sevorix-watchtower.
# Edit it there; this file is a hand-applied copy (see that directory's
# NOTES.md). SEVORIX_UNINSTALLER_VERSION below identifies which copy a machine
# actually ran.

# Deliberately no `set -e`. Every step records its own outcome, so one item
# that cannot be removed never aborts the rest, and is never silently
# swallowed either — it is listed in the summary with the command to finish it.
set -uo pipefail

SEVORIX_UNINSTALLER_VERSION="1"

ASSUME_YES=0
DRY_RUN=0
PURGE=0

fail() { printf '\n❌ %s\n' "$1" >&2; shift; for line in "$@"; do printf '   %s\n' "$line" >&2; done; exit 1; }
say()  { printf '%s\n' "$1"; }

usage() {
    cat <<'EOF'
Sevorix Pro uninstaller

Usage:
  curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/uninstall.sh | bash
  curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/uninstall.sh | bash -s -- --yes
  curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/uninstall.sh | bash -s -- --purge

Options:
  --yes        Do not ask for confirmation. Required when there is no terminal
               (CI, configuration management, image builds).
  --purge      Also delete your own Sevorix data: ~/.sevorix (policies, roles,
               settings, hooks, logs, receipts, Hub credentials, models),
               ~/.config/sevorix, and the promoted hooks in
               /usr/local/lib/sevorix/hooks.
  --dry-run    List what would be removed and what would be kept. Changes nothing.
  --help       Show this message.

Removed by default:
  /etc/sudoers.d/sevorix-{ebpf,cgroup,agent,claude}
  /usr/local/bin/{sevsh,sevorix-cgroup-helper,sevorix-agent-launcher,sevorix-agent-wrap}
  /usr/local/lib/sevorix (installed binaries; your promoted hooks are kept)
  The Sevorix TLS interception CA, untrusted from the system store, and its
    key in ~/.sevorix/ca once the untrust is confirmed
  /etc/sysctl.d/60-sevorix-userns.conf (the runtime value reverts on reboot)
  ~/.local/bin/sevorix, ~/.sevorix/bin, ~/.local/state/sevorix
  The Claude Code MCP config rewrite, restored from its backup

Kept by default: everything else in ~/.sevorix, and ~/.config/sevorix.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y) ASSUME_YES=1; shift ;;
        --purge) PURGE=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) fail "Unknown option: $1" "Run with --help for usage." ;;
    esac
done

say "--------------------------------------------------"
say "🧹 Sevorix Pro uninstaller"
say "--------------------------------------------------"

# ---------------------------------------------------------------
# Refuse to run as root.
#
# The installer installs for one user account: the binary in that user's
# ~/.local/bin, config in that user's ~/.sevorix. Under `sudo bash`, $HOME is
# /root, so every user-side path below would point at the wrong place — the
# uninstall would remove root's (nonexistent) copy and report success while the
# real one stayed. It calls sudo itself for the steps that need it.
# ---------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
    fail "Do not run this uninstaller as root." \
         "Sevorix is installed for a specific user account, and this script calls" \
         "sudo itself for the steps that need root. Re-run it as that user:" \
         "" \
         "  curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/uninstall.sh | bash"
fi

[ "$(uname -s)" = "Linux" ] || fail "This uninstaller is for Linux installs of Sevorix Pro (found: $(uname -s))."

# ---------------------------------------------------------------
# Everything the installer can have created. Kept in step with
# install-binary.sh and src/paths.rs; tests/install_container/scenarios.sh
# (scenario 22) installs through the real installer and checks that none of it
# survives an uninstall.
# ---------------------------------------------------------------
INSTALL_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.sevorix"
STATE_DIR="$HOME/.local/state/sevorix"
LEGACY_CONFIG_DIR="$HOME/.config/sevorix"
LIB_DIR="/usr/local/lib/sevorix"
HOOKS_DIR="$LIB_DIR/hooks"

# ebpf/cgroup/agent are current; claude is the pre-generalization launcher's rule.
SUDOERS_FILES=(
    /etc/sudoers.d/sevorix-ebpf
    /etc/sudoers.d/sevorix-cgroup
    /etc/sudoers.d/sevorix-agent
    /etc/sudoers.d/sevorix-claude
)
SEVSH_LINK="/usr/local/bin/sevsh"
SYSTEM_HELPERS=(
    /usr/local/bin/sevorix-cgroup-helper
    /usr/local/bin/sevorix-agent-launcher
    /usr/local/bin/sevorix-agent-wrap
    /usr/local/bin/sevorix-claude-launcher
)
LIB_FILES=(
    "$LIB_DIR/sevsh"
    "$LIB_DIR/sevsh.sha256"
    "$LIB_DIR/sevorix-verify-binary.sh"
    "$LIB_DIR/sevorix-ebpf-daemon"
    "$LIB_DIR/sevorix-ebpf"
)
DEB_CA="/usr/local/share/ca-certificates/sevorix-mitm.crt"
USER_CA_DIR="$CONFIG_DIR/ca"
USER_CA="$USER_CA_DIR/ca.crt"
USERNS_KEY="kernel.apparmor_restrict_unprivileged_userns"
USERNS_FILE="/etc/sysctl.d/60-sevorix-userns.conf"
RUN_DIR="/run/sevorix"
CGROUP_DIR="/sys/fs/cgroup/sevorix"
MCP_BACKUP="$CONFIG_DIR/integrations/claude-code-mcp-config.backup.json"
WRAPPER="$CONFIG_DIR/bin/bash"
# Older installs put these in the user-writable ~/.local/bin; the installer
# removes them on upgrade, but a machine that was never upgraded still has them.
LEGACY_USER_BINS=(
    "$INSTALL_DIR/sevsh"
    "$INSTALL_DIR/sevorix-ebpf-daemon"
    "$INSTALL_DIR/sevorix-ebpf"
)
# System trust bundles the untrust step is verified against. Debian/Ubuntu,
# Fedora/RHEL, and Arch (the last shares Debian's path).
CA_BUNDLES=(
    /etc/ssl/certs/ca-certificates.crt
    /etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem
    /etc/pki/tls/certs/ca-bundle.crt
)

REMOVED=()
KEPT=()
FAILED=()
NOTES=()

removed() { REMOVED+=("$1"); say "   ✅ removed $1"; }
kept()    { KEPT+=("$1"); }
failed()  { FAILED+=("$1"); say "   ⚠️  could not remove $1"; }
note()    { NOTES+=("$1"); }

# pem_bodies — reads PEM on stdin, prints the base64 body of each certificate
# on one line. Comparing bodies needs no openssl, which a minimal system may
# not have.
pem_bodies() {
    awk '/-----BEGIN CERTIFICATE-----/ {b=""; on=1; next}
         /-----END CERTIFICATE-----/   {if (on) print b; on=0; next}
         on {gsub(/[ \t\r]/, ""); b = b $0}'
}

# ca_trusted_anywhere <body> — succeeds if the certificate appears in any
# system trust bundle on this machine. The bundles are world-readable.
ca_trusted_anywhere() {
    local body="$1" bundle
    for bundle in "${CA_BUNDLES[@]}"; do
        [ -r "$bundle" ] || continue
        # Not `grep -q`: it exits at the first match, awk then dies of
        # SIGPIPE, and under pipefail a trusted CA would read as untrusted.
        if pem_bodies < "$bundle" | grep -Fx -- "$body" > /dev/null; then
            return 0
        fi
    done
    return 1
}

any_ca_bundle_readable() {
    local bundle
    for bundle in "${CA_BUNDLES[@]}"; do [ -r "$bundle" ] && return 0; done
    return 1
}

# ---------------------------------------------------------------
# Inventory.
#
# /etc/sudoers.d is 0750 root on most distributions, so whether those files
# exist cannot be seen without sudo. When sudo already has cached credentials
# (or is passwordless) they are checked now; otherwise they are listed as
# "checked after sudo" and resolved once sudo has been authorised.
# ---------------------------------------------------------------
HAVE_SUDO=0
command -v sudo > /dev/null 2>&1 && HAVE_SUDO=1

SUDO_READY=0
if [ "$HAVE_SUDO" -eq 1 ] && sudo -n true 2> /dev/null; then
    SUDO_READY=1
fi

PLAN_REMOVE=()
PLAN_KEEP=()
ROOT_ITEMS=0
SUDOERS_UNKNOWN=0

if [ "$SUDO_READY" -eq 1 ]; then
    for f in "${SUDOERS_FILES[@]}"; do
        if sudo test -e "$f"; then PLAN_REMOVE+=("$f  (sudoers rule)"); ROOT_ITEMS=$((ROOT_ITEMS+1)); fi
    done
elif [ "$HAVE_SUDO" -eq 1 ]; then
    SUDOERS_UNKNOWN=1
    PLAN_REMOVE+=("/etc/sudoers.d/sevorix-{ebpf,cgroup,agent,claude}  (whichever exist — checked after sudo)")
fi

if [ -L "$SEVSH_LINK" ] || [ -e "$SEVSH_LINK" ]; then PLAN_REMOVE+=("$SEVSH_LINK"); ROOT_ITEMS=$((ROOT_ITEMS+1)); fi
for f in "${SYSTEM_HELPERS[@]}"; do
    if [ -e "$f" ]; then PLAN_REMOVE+=("$f"); ROOT_ITEMS=$((ROOT_ITEMS+1)); fi
done
for f in "${LIB_FILES[@]}"; do
    if [ -e "$f" ]; then PLAN_REMOVE+=("$f"); ROOT_ITEMS=$((ROOT_ITEMS+1)); fi
done
if [ -d "$HOOKS_DIR" ]; then
    ROOT_ITEMS=$((ROOT_ITEMS+1))
    if [ "$PURGE" -eq 1 ]; then
        PLAN_REMOVE+=("$HOOKS_DIR  (your promoted hooks — --purge)")
    else
        PLAN_KEEP+=("$HOOKS_DIR  (your promoted hooks; --purge removes them)")
    fi
fi
[ -d "$LIB_DIR" ] && ROOT_ITEMS=$((ROOT_ITEMS+1))

CA_BODY=""
if [ -r "$USER_CA" ]; then
    CA_BODY="$(pem_bodies < "$USER_CA")"; CA_BODY="${CA_BODY%%$'\n'*}"
elif [ -r "$DEB_CA" ]; then
    CA_BODY="$(pem_bodies < "$DEB_CA")"; CA_BODY="${CA_BODY%%$'\n'*}"
fi
CA_TRUSTED=0
if [ -e "$DEB_CA" ] || { [ -n "$CA_BODY" ] && ca_trusted_anywhere "$CA_BODY"; }; then
    CA_TRUSTED=1
    ROOT_ITEMS=$((ROOT_ITEMS+1))
    PLAN_REMOVE+=("Sevorix TLS interception CA from the system trust store")
fi
if [ -d "$USER_CA_DIR" ]; then
    PLAN_REMOVE+=("$USER_CA_DIR  (CA certificate and private key — only once the CA is confirmed untrusted)")
fi

if [ -e "$USERNS_FILE" ]; then
    PLAN_REMOVE+=("$USERNS_FILE  (the running kernel keeps its current value until reboot)")
    ROOT_ITEMS=$((ROOT_ITEMS+1))
fi
if [ -d "$RUN_DIR" ] || [ -d "$CGROUP_DIR" ]; then
    PLAN_REMOVE+=("$RUN_DIR, $CGROUP_DIR  (runtime state, only if no session is live)")
    ROOT_ITEMS=$((ROOT_ITEMS+1))
fi

[ -f "$MCP_BACKUP" ] && PLAN_REMOVE+=("Claude Code's MCP config rewrite in ~/.claude.json  (restored from $MCP_BACKUP)")
[ -e "$INSTALL_DIR/sevorix" ] && PLAN_REMOVE+=("$INSTALL_DIR/sevorix")
for f in "${LEGACY_USER_BINS[@]}"; do [ -e "$f" ] && PLAN_REMOVE+=("$f  (left by an older install)"); done
[ -e "$WRAPPER" ] && PLAN_REMOVE+=("$CONFIG_DIR/bin  (installer-generated bash wrapper)")
[ -d "$STATE_DIR" ] && PLAN_REMOVE+=("$STATE_DIR  (PID files and session metadata)")

if [ "$PURGE" -eq 1 ]; then
    [ -d "$CONFIG_DIR" ] && PLAN_REMOVE+=("$CONFIG_DIR  (ALL of it: policies, roles, settings, hooks, logs, receipts, credentials — --purge)")
    [ -d "$LEGACY_CONFIG_DIR" ] && PLAN_REMOVE+=("$LEGACY_CONFIG_DIR  (--purge)")
else
    if [ -d "$CONFIG_DIR" ]; then
        while IFS= read -r entry; do
            case "$entry" in
                bin|ca) continue ;;
                integrations) [ -f "$MCP_BACKUP" ] && continue ;;
            esac
            PLAN_KEEP+=("$CONFIG_DIR/$entry")
        done < <(ls -A "$CONFIG_DIR" 2>/dev/null)
    fi
    [ -d "$LEGACY_CONFIG_DIR" ] && PLAN_KEEP+=("$LEGACY_CONFIG_DIR  (legacy Hub token location)")
fi

NEED_SUDO=0
if [ "$ROOT_ITEMS" -gt 0 ] || [ "$SUDOERS_UNKNOWN" -eq 1 ]; then NEED_SUDO=1; fi

if [ "${#PLAN_REMOVE[@]}" -eq 0 ]; then
    say ""
    say "Nothing from a Sevorix install was found for $(id -un) on this machine."
    if [ "${#PLAN_KEEP[@]}" -gt 0 ]; then
        say "Your own Sevorix data is still here (run with --purge to delete it):"
        for item in "${PLAN_KEEP[@]}"; do say "  • $item"; done
    fi
    exit 0
fi

say ""
say "This will remove:"
for item in "${PLAN_REMOVE[@]}"; do say "  • $item"; done
if [ "${#PLAN_KEEP[@]}" -gt 0 ]; then
    say ""
    say "This will keep (your own data — run with --purge to delete it too):"
    for item in "${PLAN_KEEP[@]}"; do say "  • $item"; done
fi
if [ "$NEED_SUDO" -eq 1 ]; then
    say ""
    say "Removing the root-owned items needs sudo."
fi

if [ "$DRY_RUN" -eq 1 ]; then
    say ""
    say "Dry run — nothing was changed."
    exit 0
fi

# ---------------------------------------------------------------
# Confirm once, default No.
#
# The same terminal handling as install.sh: under `curl … | bash`, stdin is
# this script, so the answer is read from /dev/tty. The test opens it rather
# than asking `test -r`, which says yes in a container with no controlling
# terminal and then fails to open. No terminal and no --yes means stop, having
# changed nothing — end-of-file is never a yes.
# ---------------------------------------------------------------
if [ "$ASSUME_YES" -ne 1 ]; then
    if ! ( : < /dev/tty ) 2>/dev/null; then
        fail "No terminal available to confirm the uninstall." \
             "" \
             "Nothing was changed. To uninstall without a prompt (CI, configuration" \
             "management, image builds):" \
             "" \
             "  curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/uninstall.sh | bash -s -- --yes"
    fi
    say ""
    printf 'Proceed with the uninstall? [y/N] '
    answer=""
    read -r answer < /dev/tty || answer=""
    case "$answer" in
        [yY]|[yY][eE][sS]) ;;
        *) say ""; say "Cancelled — nothing was changed."; exit 0 ;;
    esac
fi

# ---------------------------------------------------------------
# Authorise sudo up front.
#
# If root cannot be had, stop here with nothing changed. Carrying on with only
# the user-side half would leave the passwordless root grants in place while
# removing the tooling that would show they exist — a worse state than either
# "installed" or "uninstalled".
#
# `sudo true`, not `sudo -v`. With sudo's default verifypw=all, -v succeeds
# without authenticating when every rule the user has is NOPASSWD — and the
# three rules Sevorix installed are exactly that. On an account with no other
# sudo rights, -v would pass here and every removal after it would fail.
# Running a real command proves the user may actually run commands as root.
# ---------------------------------------------------------------
if [ "$NEED_SUDO" -eq 1 ]; then
    if [ "$HAVE_SUDO" -ne 1 ]; then
        fail "Root-owned Sevorix files are installed, but 'sudo' is not available." \
             "Nothing was changed. Run this script as a user who can use sudo."
    fi
    say ""
    say "==> Authorising sudo"
    if ! sudo true; then
        fail "sudo was not authorised." \
             "Nothing was changed. The root-owned items listed above are still installed."
    fi
    SUDO_READY=1
fi

# ---------------------------------------------------------------
# 1. Stop the daemon.
#
# Best effort: a missing or broken binary is not a reason to leave passwordless
# root grants in place. Anything still running afterwards is reported.
# ---------------------------------------------------------------
say ""
say "==> Stopping Sevorix"
if [ -x "$INSTALL_DIR/sevorix" ]; then
    if command -v timeout > /dev/null 2>&1; then
        timeout 30 "$INSTALL_DIR/sevorix" stop > /dev/null 2>&1 || true
    else
        "$INSTALL_DIR/sevorix" stop > /dev/null 2>&1 || true
    fi
    sleep 1
    say "   ✅ sevorix stop issued"
else
    say "   ℹ️  $INSTALL_DIR/sevorix not present — nothing to stop"
fi

# ---------------------------------------------------------------
# 2. Restore Claude Code's MCP config.
#
# `sevorix integrations install claude-code` rewrote ~/.claude.json so every
# MCP server launches through /usr/local/lib/sevorix/sevsh. Removing sevsh
# without undoing that leaves Claude Code unable to start any MCP server. This
# needs the sevorix binary, so it runs before the binary is removed. The CLI
# reports failure on stderr without a failing exit status, so success is judged
# by the backup having been consumed.
# ---------------------------------------------------------------
MCP_RESTORE_FAILED=0
if [ -f "$MCP_BACKUP" ]; then
    say ""
    say "==> Restoring Claude Code's MCP config"
    if [ -x "$INSTALL_DIR/sevorix" ]; then
        "$INSTALL_DIR/sevorix" integrations uninstall claude-code > /dev/null 2>&1 || true
    fi
    if [ -f "$MCP_BACKUP" ]; then
        MCP_RESTORE_FAILED=1
        FAILED+=("Claude Code MCP config not restored — the pre-Sevorix copy is kept at $MCP_BACKUP; compare it with ~/.claude.json and copy its mcpServers back")
        say "   ⚠️  could not restore it automatically; the backup is kept"
    else
        removed "Claude Code MCP config rewrite (restored ~/.claude.json)"
    fi
fi

# ---------------------------------------------------------------
# 3. Sudoers rules — revoked before the binaries they name.
#
# One exact path per `rm`, never a glob. A file is removed only if it is
# recognisably a Sevorix rule, so an administrator's own file that happens to
# share a name is left alone. Unlinking is atomic, so there is no partially
# written file for sudo to trip over; each removal is then confirmed.
# ---------------------------------------------------------------
if [ "$SUDO_READY" -eq 1 ]; then
    say ""
    say "==> Revoking passwordless sudo rules"
    touched_sudoers=0
    for f in "${SUDOERS_FILES[@]}"; do
        sudo test -e "$f" || continue
        touched_sudoers=1
        if ! sudo grep -qE 'NOPASSWD:.*sevorix' "$f" 2>/dev/null; then
            kept "$f  (does not look like a Sevorix rule — left for you to review)"
            say "   ℹ️  left $f — it does not look like a Sevorix rule"
            continue
        fi
        sudo rm -f -- "$f"
        if sudo test -e "$f"; then
            failed "$f  → sudo rm -f -- $f"
        else
            removed "$f"
        fi
    done
    if [ "$touched_sudoers" -eq 0 ]; then
        say "   ℹ️  none installed"
    elif command -v visudo > /dev/null 2>&1 && ! sudo visudo -c > /dev/null 2>&1; then
        note "sudo visudo -c reports a problem in the sudoers configuration. This script only deletes files, so it predates the uninstall — run 'sudo visudo -c' to see it."
    fi
fi

# ---------------------------------------------------------------
# 4. Untrust the TLS interception CA.
#
# Reverses exactly what install-binary.sh did: the Debian path copies the cert
# into /usr/local/share/ca-certificates and runs update-ca-certificates (whose
# own "TO UNDO" is removing the file and `update-ca-certificates --fresh`); the
# p11-kit path ran `trust anchor --store`, reversed with `trust anchor
# --remove`, which needs the certificate file — so this runs before
# ~/.sevorix/ca is touched. Success is not assumed from exit statuses: the
# system bundles are re-read and the certificate must be absent from all of them.
# ---------------------------------------------------------------
CA_UNTRUST_CONFIRMED=0
if [ "$CA_TRUSTED" -eq 1 ]; then
    say ""
    say "==> Removing the Sevorix CA from the system trust store"
    if [ -e "$DEB_CA" ]; then
        sudo rm -f -- "$DEB_CA"
        if [ -e "$DEB_CA" ]; then
            failed "$DEB_CA  → sudo rm -f $DEB_CA && sudo update-ca-certificates --fresh"
        elif command -v update-ca-certificates > /dev/null 2>&1; then
            sudo update-ca-certificates --fresh > /dev/null 2>&1 \
                || say "   ⚠️  update-ca-certificates --fresh reported an error"
        fi
    fi
    if [ -n "$CA_BODY" ] && ca_trusted_anywhere "$CA_BODY" \
        && command -v trust > /dev/null 2>&1 && [ -r "$USER_CA" ]; then
        sudo trust anchor --remove "$USER_CA" > /dev/null 2>&1 \
            || say "   ⚠️  trust anchor --remove reported an error"
    fi

    if [ -z "$CA_BODY" ]; then
        if [ ! -e "$DEB_CA" ]; then
            removed "$DEB_CA (CA untrusted)"
        fi
        note "The CA certificate itself was not found, so its absence from the trust store could not be double-checked."
    elif ca_trusted_anywhere "$CA_BODY"; then
        FAILED+=("Sevorix CA is still in the system trust store → sudo trust anchor --remove $USER_CA  (or remove it from your distribution's CA directory and rebuild the bundle)")
        say "   ⚠️  the CA is still trusted"
    else
        CA_UNTRUST_CONFIRMED=1
        removed "Sevorix TLS interception CA (no longer in the system trust store)"
    fi
elif [ -n "$CA_BODY" ] && any_ca_bundle_readable; then
    # Never trusted, and confirmed so: the key can go.
    CA_UNTRUST_CONFIRMED=1
fi

# ---------------------------------------------------------------
# 5. The userns sysctl drop-in.
#
# install-binary.sh wrote this to disable Ubuntu 24.04+'s AppArmor restriction
# on unprivileged user namespaces, system-wide. Only the file is removed: the
# running kernel keeps its current value until the next reboot, at which point
# the distribution default applies again. That is stated in the summary rather
# than left for the user to discover.
# ---------------------------------------------------------------
if [ -e "$USERNS_FILE" ]; then
    say ""
    say "==> Removing the userns sysctl drop-in"
    sudo rm -f -- "$USERNS_FILE"
    if [ -e "$USERNS_FILE" ]; then
        failed "$USERNS_FILE  → sudo rm -f $USERNS_FILE"
    else
        removed "$USERNS_FILE"
        current="$(sysctl -n "$USERNS_KEY" 2>/dev/null || true)"
        if [ "$current" = "0" ]; then
            note "$USERNS_KEY is still 0 in the running kernel — unprivileged user namespaces stay unrestricted system-wide until you reboot. To restore the restriction now: sudo sysctl -w $USERNS_KEY=1"
        elif [ -n "$current" ]; then
            note "$USERNS_KEY is $current in the running kernel; with the drop-in gone, the distribution default applies from the next boot."
        else
            note "Removed the userns drop-in, but $USERNS_KEY could not be read here. Whatever value the drop-in applied stays in the running kernel until you reboot."
        fi
    fi
fi

# ---------------------------------------------------------------
# 6. Root-owned binaries.
#
# The lib dir is emptied file by file rather than `rm -rf`'d: it also holds
# /usr/local/lib/sevorix/hooks, the root-owned directory your own hooks are
# promoted into, which is your configuration and stays unless you --purge.
# ---------------------------------------------------------------
if [ "$SUDO_READY" -eq 1 ]; then
    say ""
    say "==> Removing privileged binaries"

    if [ -L "$SEVSH_LINK" ]; then
        case "$(readlink "$SEVSH_LINK")" in
            "$LIB_DIR"/*)
                sudo rm -f -- "$SEVSH_LINK"
                if [ -L "$SEVSH_LINK" ]; then failed "$SEVSH_LINK  → sudo rm -f $SEVSH_LINK"; else removed "$SEVSH_LINK"; fi
                ;;
            *)
                kept "$SEVSH_LINK  (points at $(readlink "$SEVSH_LINK"), not at $LIB_DIR — left for you to review)"
                ;;
        esac
    elif [ -e "$SEVSH_LINK" ]; then
        kept "$SEVSH_LINK  (a regular file, not the installer's symlink — left for you to review)"
    fi

    for f in "${SYSTEM_HELPERS[@]}" "${LIB_FILES[@]}"; do
        [ -e "$f" ] || [ -L "$f" ] || continue
        sudo rm -f -- "$f"
        if [ -e "$f" ] || [ -L "$f" ]; then failed "$f  → sudo rm -f $f"; else removed "$f"; fi
    done

    if [ -d "$HOOKS_DIR" ]; then
        if [ "$PURGE" -eq 1 ]; then
            sudo rm -rf -- "$HOOKS_DIR"
            if [ -d "$HOOKS_DIR" ]; then failed "$HOOKS_DIR  → sudo rm -rf $HOOKS_DIR"; else removed "$HOOKS_DIR"; fi
        else
            kept "$HOOKS_DIR  (your promoted hooks)"
        fi
    fi

    if [ -d "$LIB_DIR" ]; then
        if sudo rmdir -- "$LIB_DIR" 2>/dev/null; then
            removed "$LIB_DIR"
        else
            # Anything other than the kept hooks is something the installer
            # never put there. Listed, not deleted.
            unknown="$(find "$LIB_DIR" -mindepth 1 -maxdepth 1 ! -name hooks -printf '%f ' 2>/dev/null)"
            [ -n "$unknown" ] && kept "$LIB_DIR  (contains files the installer did not create: $unknown)"
        fi
    fi

    # Runtime state. tmpfs and cgroupfs, so a reboot clears both; removed now
    # only if nothing is using them. rmdir cannot remove a cgroup that still
    # has processes, which is exactly the guarantee wanted.
    if [ -d "$CGROUP_DIR" ]; then
        sudo find "$CGROUP_DIR" -mindepth 1 -depth -type d -exec rmdir {} \; 2>/dev/null
        if sudo rmdir -- "$CGROUP_DIR" 2>/dev/null; then
            removed "$CGROUP_DIR"
        else
            note "$CGROUP_DIR still has live sessions in it — it is cleared on reboot, or once those sessions exit."
        fi
    fi
    if [ -d "$RUN_DIR" ]; then
        sudo rmdir -- "$RUN_DIR/sessions" 2>/dev/null
        if sudo rmdir -- "$RUN_DIR" 2>/dev/null; then
            removed "$RUN_DIR"
        else
            note "$RUN_DIR still holds state for a live agent session — it is on tmpfs and cleared on reboot."
        fi
    fi
fi

# ---------------------------------------------------------------
# 7. User-side files.
# ---------------------------------------------------------------
say ""
say "==> Removing user files"

rm_user() {
    local path="$1"
    [ -e "$path" ] || [ -L "$path" ] || return 0
    rm -rf -- "$path" 2>/dev/null
    # Older installs left the eBPF daemon in ~/.local/bin as root; the
    # installer removed those copies with sudo too.
    if { [ -e "$path" ] || [ -L "$path" ]; } && [ "$SUDO_READY" -eq 1 ]; then
        sudo rm -rf -- "$path"
    fi
    if [ -e "$path" ] || [ -L "$path" ]; then failed "$path  → rm -rf $path"; else removed "$path"; fi
}

rm_user "$INSTALL_DIR/sevorix"
for f in "${LEGACY_USER_BINS[@]}"; do rm_user "$f"; done
rm_user "$STATE_DIR"

if [ -e "$WRAPPER" ]; then
    if grep -q '/usr/local/bin/sevsh' "$WRAPPER" 2>/dev/null; then
        rm_user "$WRAPPER"
        rmdir -- "$CONFIG_DIR/bin" 2>/dev/null || kept "$CONFIG_DIR/bin  (contains files the installer did not create)"
    else
        kept "$WRAPPER  (not the installer's wrapper — left for you to review)"
    fi
fi

if [ -d "$USER_CA_DIR" ]; then
    if [ "$CA_UNTRUST_CONFIRMED" -eq 1 ]; then
        rm_user "$USER_CA_DIR"
    else
        kept "$USER_CA_DIR  (the CA could not be confirmed untrusted, so its certificate is kept for you to finish that — delete this directory afterwards: it holds the CA's private key)"
    fi
fi

if [ "$MCP_RESTORE_FAILED" -eq 0 ] && [ -d "$CONFIG_DIR/integrations" ]; then
    rmdir -- "$CONFIG_DIR/integrations" 2>/dev/null || true
fi

if [ "$PURGE" -eq 1 ]; then
    if [ -d "$CONFIG_DIR" ]; then
        # What an earlier step deliberately preserved stays preserved: the
        # MCP backup is the only copy of the user's original config, and the CA
        # certificate is needed to finish untrusting it.
        while IFS= read -r entry; do
            [ "$entry" = "integrations" ] && [ "$MCP_RESTORE_FAILED" -eq 1 ] && continue
            [ "$entry" = "ca" ] && [ "$CA_UNTRUST_CONFIRMED" -ne 1 ] && continue
            rm_user "$CONFIG_DIR/$entry"
        done < <(ls -A "$CONFIG_DIR" 2>/dev/null)
        if rmdir -- "$CONFIG_DIR" 2>/dev/null; then removed "$CONFIG_DIR"; fi
    fi
    rm_user "$LEGACY_CONFIG_DIR"
else
    if [ -d "$CONFIG_DIR" ]; then
        while IFS= read -r entry; do
            case "$entry" in ca|integrations|bin) continue ;; esac
            kept "$CONFIG_DIR/$entry"
        done < <(ls -A "$CONFIG_DIR" 2>/dev/null)
        # Nothing of the user's in it: no reason to leave an empty directory.
        rmdir -- "$CONFIG_DIR" 2>/dev/null && removed "$CONFIG_DIR (empty)"
    fi
    [ -d "$LEGACY_CONFIG_DIR" ] && kept "$LEGACY_CONFIG_DIR  (legacy Hub token location)"
fi

# ---------------------------------------------------------------
# Things this script does not edit, but should not stay silent about.
# ---------------------------------------------------------------
if pgrep -u "$(id -u)" -x sevorix > /dev/null 2>&1; then
    note "A sevorix process is still running (it was started before the binary was removed). Stop it with: pkill -u $(id -un) -x sevorix"
fi
for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile" "$HOME/.bash_profile"; do
    [ -r "$rc" ] || continue
    line="$(grep -n 'NODE_EXTRA_CA_CERTS=.*\.sevorix' "$rc" 2>/dev/null || true)"
    line="${line%%$'\n'*}"
    [ -n "$line" ] && note "$rc line ${line%%:*} still exports NODE_EXTRA_CA_CERTS pointing into ~/.sevorix — remove that line."
done

# ---------------------------------------------------------------
# Summary.
# ---------------------------------------------------------------
say ""
say "--------------------------------------------------"
say "Summary"
say "--------------------------------------------------"
say ""
say "Removed (${#REMOVED[@]}):"
if [ "${#REMOVED[@]}" -eq 0 ]; then say "  (nothing)"; fi
for item in "${REMOVED[@]}"; do say "  ✅ $item"; done

if [ "${#KEPT[@]}" -gt 0 ]; then
    say ""
    say "Left in place, deliberately (${#KEPT[@]}):"
    for item in "${KEPT[@]}"; do say "  📁 $item"; done
    if [ "$PURGE" -ne 1 ]; then
        say "  Run again with --purge to delete your own Sevorix data too."
    fi
fi

if [ "${#NOTES[@]}" -gt 0 ]; then
    say ""
    say "Notes:"
    for item in "${NOTES[@]}"; do say "  ℹ️  $item"; done
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
    say ""
    say "Could NOT be removed (${#FAILED[@]}) — finish these by hand:"
    for item in "${FAILED[@]}"; do say "  ❌ $item"; done
    say ""
    exit 1
fi

say ""
say "Sevorix has been uninstalled."

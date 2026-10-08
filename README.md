# 🛡️ Sevorix Pro

> **Runtime Containment for Autonomous AI Agents.**
> *Zero-Latency. Action-Centric. Rust-Native.*

![Rust](https://img.shields.io/badge/built%20with-Rust-orange) ![Platform](https://img.shields.io/badge/platform-Linux%20x86__64%20%7C%20macOS%20arm64-lightgrey) ![Latest release](https://img.shields.io/github/v/release/sevorix/sevorix)

Most "AI Gateway" products only look at the prompt going in. If your agent gets a
raw shell command or a direct network socket, it bypasses that entirely.

Sevorix is a local runtime firewall that enforces an inescapable **Action
Authorization Boundary** on your AI agents. It sits on the wire between the agent
and the outside world — shell, network, and the kernel itself — and intercepts,
records, and blocks dangerous activity in < 20ms. What counts as dangerous is
completely up to you.

---

## 📦 What this repository is

**This repository distributes compiled binaries of Sevorix Pro.**

Sevorix Pro is proprietary, commercially licensed software. Its source code is
not published here or anywhere else, and is not made available to customers,
evaluators or partners. Every release below is a build published by CI from a
private source tree.

- **Downloads:** the [releases page](https://github.com/sevorix/sevorix/releases/latest)
- **Pricing and licensing:** [sevorix.com](https://sevorix.com)
- **Separate open-source edition:** [sevorix/sevorix-lite](https://github.com/sevorix/sevorix-lite) — Sevorix *Lite*, AGPL-3.0. Lite is a distinct product with its own, smaller feature set; it is not a source release of Pro.

**Currently shipped:** Linux x86_64 (including WSL2) and macOS on Apple Silicon.
Intel Macs are not supported. macOS gets a subset of the Linux feature set — see
[Sevorix on macOS](#-sevorix-on-macos) for exactly what is and is not available.

> The "Source code (zip/tar.gz)" archives attached to each release are generated
> automatically by GitHub from this repository's own contents — which is this
> README and the install/uninstall scripts, nothing else. They are **not** Sevorix source code, and are not a
> source release of any kind.

---

## 🔑 Before you start: Pro requires an active subscription

Sevorix Pro verifies your subscription when the daemon starts. `sevorix start`
contacts Sevorix Hub, checks that the logged-in account has an active
subscription, and **refuses to start** if it does not — there is no offline or
degraded mode.

So the order matters:

```bash
sevorix hub login     # or: sevorix hub register
sevorix start
```

If you do not have a subscription yet, start with
**[Sevorix Lite](https://github.com/sevorix/sevorix-lite)** — same enforcement
core, open source, no account required.

---

## ⚡ Quick start

### Linux (x86_64, including WSL2)

```bash
curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/install.sh | bash
```

### macOS (Apple Silicon)

```bash
curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/install-macos.sh | bash
```

Apple Silicon (M-series) only — Intel Macs are not supported. macOS has a
smaller feature set than Linux; read [Sevorix on macOS](#-sevorix-on-macos)
before you rely on it.

---

Each script downloads the latest release for its platform, verifies its SHA-256,
and runs the bundle's own installer — which **prompts before every privileged
step** and explains what each one is for, even when the script itself arrived
through a pipe.

For an unattended install (CI, cloud-init, image builds), accept those steps up
front with `--yes`:

```bash
curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/install.sh | bash -s -- --yes         # Linux
curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/install-macos.sh | bash -s -- --yes   # macOS
```

Useful flags (both scripts): `--version X.Y.Z` to pin a release, `--dry-run` to
see what would happen, `--help` for the rest.

Then [log in and start](#4-log-in-and-start).

> Piping a script to a shell means running code you have not read. If you would
> rather not, the same install is four commands below — and you can read the
> scripts first: they are
> [`install.sh`](https://github.com/sevorix/sevorix/blob/main/install.sh) and
> [`install-macos.sh`](https://github.com/sevorix/sevorix/blob/main/install-macos.sh)
> in this repository.

---

## 🔧 Manual install

### 1. Download

Pick your platform — `x86_64-linux` for Linux (including WSL2), `aarch64-macos`
for a Mac with Apple Silicon:

```bash
PLATFORM=x86_64-linux   # or: PLATFORM=aarch64-macos
VERSION=$(curl -s https://api.github.com/repos/sevorix/sevorix/releases/latest | grep tag_name | cut -d'"' -f4)
curl -LO https://github.com/sevorix/sevorix/releases/download/${VERSION}/sevorix-pro-${VERSION}-${PLATFORM}.tar.gz
curl -LO https://github.com/sevorix/sevorix/releases/download/${VERSION}/sevorix-pro-${VERSION}-${PLATFORM}.tar.gz.sha256
```

On macOS, download with `curl` as shown rather than through a browser: the macOS
binaries are not notarized by Apple, and macOS refuses to run un-notarized
binaries that a browser downloaded until you clear the quarantine flag
(`xattr -dr com.apple.quarantine sevorix-pro-${VERSION}-${PLATFORM}`).

### 2. Verify the download

Not optional. On Linux the installer asks for `sudo` and installs a root-owned
binary that every shell command on your machine will be routed through. Check the
archive before you extract it:

```bash
sha256sum -c sevorix-pro-${VERSION}-${PLATFORM}.tar.gz.sha256          # Linux
shasum -a 256 -c sevorix-pro-${VERSION}-${PLATFORM}.tar.gz.sha256      # macOS
```

The expected checksum is also printed in the release notes, so you can compare it
against a second source rather than against a file downloaded from the same place
as the archive.

### 3. Install

```bash
tar xzf sevorix-pro-${VERSION}-${PLATFORM}.tar.gz
cd sevorix-pro-${VERSION}-${PLATFORM}
./install-binary.sh          # Linux
./install-binary-macos.sh    # macOS
```

The installer prompts before every privileged step and explains what each one is
for. See [What gets installed where](#-what-gets-installed-where) below.

### 4. Log in and start

```bash
sevorix hub login
sevorix start
sevorix status
```

#### Activating a role

Every `sevsh` command is evaluated against a **role** — the set of policies that
applies to it. If no role is active, `sevsh` refuses every command with *"No role
configured for this session"*.

The installer activates the `default` role for you when it pulls the default
policies and roles and you have no `~/.sevorix/settings.json` yet. (The macOS
installer does this from the first release after 1.0.2; on 1.0.2 itself, set it
by hand as below.) If you declined that pull, already had a `settings.json`, or
want a different role, set it yourself in `~/.sevorix/settings.json`:

```json
{
  "sevsh": { "default_role": "default" }
}
```

If the file already exists, add the `"sevsh"` key to it rather than replacing
the file — an unreadable `settings.json` is ignored as a whole, which would
quietly turn off every other setting in it. Then restart the daemon
(`sevorix stop && sevorix start`): `default_role` is read only at startup, and
`sevorix start` refuses to start if it names a role you have not installed.

### 5. Open the Observatory

`sevorix start` prints a session token. Open your local command center:

👉 `http://localhost:3000/dashboard/desktop.html?token=<session-token>`

If you lose the token, `sevorix status` prints it again.

---

## 🍎 Sevorix on macOS

The macOS build is a native Apple Silicon (arm64) binary. Much of Sevorix's
enforcement on Linux is built on Linux kernel features that macOS does not have,
so the macOS build is a **subset** of the Linux one — not the same product on a
different OS.

**Available on macOS:**

- the HTTP proxy, including inbound (response) scanning and TLS inspection
- the policy engine, roles, and `sevorix validate`
- `sevsh`, the policy-checked shell wrapper — commands you run through it are
  evaluated against your policies before they execute
- the Observatory dashboard and live traffic feed
- the Pro features: Jury of Rivals, the prompt-injection classifier, built-in
  self-protection policies, signed receipts, JSON hooks, log export

**Linux only — not available on macOS:**

- **eBPF syscall monitoring** and **seccomp syscall interception.** Nothing
  is enforced at the kernel level: a command that does not go through `sevsh`,
  and traffic that does not go through the proxy, is not seen.
- **Agent integrations** (`sevorix integrations start claude-code`/`codex`).
  They depend on a privileged Linux mount-namespace launcher that binds `sevsh`
  over `/bin/bash`; on macOS an agent has to be pointed at `sevsh` itself.
- **Session containment.** On Linux, while a flagged command waits for your
  decision, the rest of the agent's processes are frozen. macOS has no
  equivalent: the flagged command itself is still held until you decide, but
  the agent's other processes keep running in the meantime. macOS therefore
  defaults `intervention.containment` to `"best_effort"` (review without
  suspension), where Linux defaults to `"required"`. If you would rather have
  every flagged action blocked outright on macOS, set it explicitly:
  ```json
  { "intervention": { "containment": "required" } }
  ```
  **On 1.0.2** the macOS default is still `"required"`, so flagged actions are
  blocked outright until you set `"best_effort"` in `~/.sevorix/settings.json`.
- **The uninstaller** (`uninstall.sh`). See
  [What gets installed where](#-what-gets-installed-where) for removing Sevorix
  from a Mac by hand.

**Notarization.** The macOS binaries are not notarized by Apple. Installing with
`curl` (either the one-liner or the manual steps) is unaffected. If you download
the archive in a browser instead, macOS will refuse to run the binaries until you
clear the quarantine flag on the extracted bundle:
`xattr -dr com.apple.quarantine sevorix-pro-<version>-aarch64-macos`.

---

## 🏎️ The test drive: see it in action

Don't trust us. Test it. `sevsh` is a secure shell wrapper that routes commands
through the Sevorix engine before they ever reach the processor.

Leave the Observatory open in a browser and run these in your terminal:

### Scenario 1 — The Green Lane (allowed)

```bash
sevsh -c "echo 'Agent is thinking...'"
```

**Result:** the command executes normally.

### Scenario 2 — The Red Lane (zero-latency kill switch)

A rogue agent trying to drop a database table. The default policies forbid `DROP`.

```bash
sevsh -c "DROP TABLE users;"
```

**Result:** the command is vaporized. You see `SEVORIX BLOCKED: Policy Violation`.

### Scenario 3 — The Yellow Lane (human in the loop)

An agent reaching for sensitive data. The default policies flag `SELECT` for
review.

```bash
sevsh -c "SELECT * FROM admin_credentials;"
```

**Result:** the terminal hangs. Switch to the Observatory — a Yellow intervention
panel is waiting with a countdown. Click **Block** or **Allow** to decide. While
the review is open, the rest of the agent's process tree is frozen, so nothing
else runs behind your back while you think.

> **If the command is blocked outright instead**, session containment is not
> available — most often because the cgroup helper prompt was declined during
> install. Sevorix will not hold a review it cannot contain: if the agent cannot
> be suspended while you decide, the flagged action is denied rather than left
> running. Re-run `./install-binary.sh` and accept the cgroup helper, or set
> `intervention.containment` to `"best_effort"` in `~/.sevorix/settings.json` to
> review without suspension. `sevorix start` warns about this at startup.
>
> **On macOS** there is nothing to suspend the agent with, so the review is
> held without suspension (`"best_effort"` is the macOS default) and the
> dashboard shows it as **not frozen**. On 1.0.2 the macOS default is still
> `"required"` and the command is blocked outright; set `"best_effort"` to see
> the review panel. See [Sevorix on macOS](#-sevorix-on-macos).

---

## 💎 What Pro adds over Lite

| | Lite | Pro |
|---|---|---|
| Shell, network and syscall enforcement¹ | ✅ | ✅ |
| `sevsh`, seccomp interception, agent sandboxing¹ | ✅ | ✅ |
| The Observatory and live traffic feed | ✅ | ✅ |
| **Jury of Rivals** — ambiguous actions adjudicated by multiple LLMs in consensus | — | ✅ |
| **Prompt-injection classifier** — ML scoring of outbound and inbound content | — | ✅ |
| **Built-in self-protection policies** — controls an agent cannot disable | — | ✅ |
| **Signed receipts** — a cryptographically verifiable audit trail | — | ✅ |
| **JSON hooks** — custom verdict logic from a root-owned directory | — | ✅ |
| **Concurrent sessions** — Lite runs one at a time | 1 | many |
| **Log export** to external sinks | — | ✅ |

¹ Syscall enforcement, seccomp interception and agent sandboxing are Linux only.
On macOS, shell (`sevsh`) and network enforcement are available — see
[Sevorix on macOS](#-sevorix-on-macos).

---

## 🤖 AI agent integrations

Sevorix puts autonomous coding agents in a secure sandbox — a mount namespace
with `sevsh` bound over `/bin/bash`, so the agent's shell commands are intercepted
even when it calls `/bin/bash` by absolute path.

```bash
sevorix integrations install claude-code
sevorix integrations start claude-code
```

**Claude Code** and **Codex** are supported today. **OpenClaw** is in active
development — `integrations start` works for it, the install/uninstall lifecycle
does not yet.

**Integrations are Linux only.** The sandbox is a Linux mount namespace set up by
a privileged launcher that the macOS build does not include.

---

## 🔧 What gets installed where

`install-binary.sh` asks for `sudo`, and it should be obvious why. Anything that
runs as root — or that root is pointed at — is installed to a root-owned location,
never under your home directory, because a location you can write to is a location
a compromised agent running as you can write to.

| Path | What | Owner |
|---|---|---|
| `~/.local/bin/sevorix` | The daemon and CLI | you |
| `/usr/local/lib/sevorix/sevsh` | The shell wrapper, plus its recorded SHA-256 | `root:root` |
| `/usr/local/bin/sevsh` | PATH-visible symlink to the above | `root:root` |
| `/usr/local/lib/sevorix/sevorix-ebpf-daemon` | Kernel-level syscall tracing | `root:root` |
| `/usr/local/bin/sevorix-cgroup-helper` | Per-session process containment | `root:root` |
| `/usr/local/bin/sevorix-agent-launcher` | Privileged agent sandbox launcher | `root:root` |
| `/usr/local/bin/sevorix-agent-wrap` | Puts a launched agent's process tree in a Sevorix cgroup | `root:root` |
| `/etc/sudoers.d/sevorix-*` | Passwordless invocation of the helpers above | `root:root` |
| `/usr/local/share/ca-certificates/sevorix-mitm.crt` | TLS interception CA, only if you enable TLS inspection and accept trusting it | `root:root` |
| `/etc/sysctl.d/60-sevorix-userns.conf` | Re-enables unprivileged user namespaces on Ubuntu 24.04+, only if you accept it | `root:root` |
| `~/.sevorix/policies`, `~/.sevorix/roles` | Your policy and role definitions | you |
| `~/.local/state/sevorix/` | PID files and session metadata | you |

Every prompt is optional and the installer tells you what is lost by declining.
Run `./install-binary.sh --force` to accept all of them non-interactively.

**On macOS** none of the root-owned pieces above exist — they are Linux mount
namespace, cgroup and eBPF machinery. `install-binary-macos.sh` installs
`sevorix` and `sevsh` to `~/.local/bin`, creates the same `~/.sevorix` and
`~/.local/state/sevorix` directories, and uses `sudo` for one thing only:
adding the TLS interception CA to the System Keychain, once you have enabled TLS
inspection and a CA has been generated (re-run the installer after first start
to do this). It asks before that step like any other, and treats no answer as
"no"; `--force` accepts it. (The 1.0.2 bundle runs it without asking.) The
uninstaller below is Linux-only; on macOS, `sevorix stop` and remove
`~/.local/bin/sevorix`, `~/.local/bin/sevsh` and (if you want your configuration
gone too) `~/.sevorix`; if you trusted the TLS interception CA, remove
"Sevorix" from the System Keychain in Keychain Access.

---

## 🗑️ Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/uninstall.sh | bash
```

It lists everything it will remove and everything it will keep, asks once, and
then asks for `sudo`. It stops the daemon, then removes the following:

- the passwordless sudoers rules
- the root-owned binaries
- the sevorix binary
- the TLS interception CA. It takes the CA out of the system trust store, then
  checks that it is really gone before deleting its key.
- the userns sysctl drop-in. The running kernel keeps its current value until
  you reboot, and the script tells you so.
- Claude Code's MCP config rewrite, which it restores from its backup

**Your own configuration stays** unless you ask for it to go. That covers
`~/.sevorix` (policies, roles, settings, hooks, logs, receipts, Hub
credentials), `~/.config/sevorix`, and hooks you promoted into
`/usr/local/lib/sevorix/hooks`. To delete those too:

```bash
curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/uninstall.sh | bash -s -- --purge
```

`--yes` skips the confirmation (required without a terminal), and `--dry-run`
shows what would happen. If anything cannot be removed, the summary names it
with the command to finish the job, and the script exits non-zero. The script is
[`uninstall.sh`](https://github.com/sevorix/sevorix/blob/main/uninstall.sh) in
this repository.

---

## 🆘 Support

📧 **support@sevorix.com** · 🌐 **[sevorix.com](https://sevorix.com)**

## 📄 Licensing

**Sevorix Pro is proprietary software, licensed commercially. It is not open
source.**

These binaries are made available under Sevorix's commercial licence terms. Your
right to use them depends on an active subscription. Downloading a release does
not grant a licence to use, redistribute, sublicense, rent, or resell the
software, nor to reverse engineer, decompile or disassemble it except where that
right cannot be excluded by applicable law.

**No source code is provided.** Sevorix does not distribute, escrow or otherwise
make available the source code of Sevorix Pro, to customers or to anyone else.
Requests for source will not be fulfilled.

Full terms: [sevorix.com](https://sevorix.com) · licensing questions:
support@sevorix.com

**Sevorix Lite** is a separate product, distributed under the AGPL-3.0 at
[sevorix/sevorix-lite](https://github.com/sevorix/sevorix-lite). Its licence
covers Lite only and confers no rights in Sevorix Pro.

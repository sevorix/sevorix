# 🛡️ Sevorix Pro

> **Runtime Containment for Autonomous AI Agents.**
> *Zero-Latency. Action-Centric. Rust-Native.*

![Rust](https://img.shields.io/badge/built%20with-Rust-orange) ![Platform](https://img.shields.io/badge/platform-Linux%20x86__64-lightgrey) ![Latest release](https://img.shields.io/github/v/release/sevorix/sevorix)

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

**Currently shipped:** Linux x86_64 (including WSL2). macOS is not yet published
here; the Lite edition builds on macOS from source today.

> The "Source code (zip/tar.gz)" archives attached to each release are generated
> automatically by GitHub from this repository's own contents — which is this
> README and nothing else. They are **not** Sevorix source code, and are not a
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

```bash
curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/install.sh | bash
```

Linux x86_64 (including WSL2). The script downloads the latest release, verifies
its SHA-256, and runs the bundle's installer — which **prompts before every
privileged step** and explains what each one is for, even when the script itself
arrived through a pipe.

For an unattended install (CI, cloud-init, image builds), accept those steps up
front with `--yes`:

```bash
curl -fsSL https://raw.githubusercontent.com/sevorix/sevorix/main/install.sh | bash -s -- --yes
```

Useful flags: `--version X.Y.Z` to pin a release, `--dry-run` to see what would
happen, `--help` for the rest.

Then [log in and start](#4-log-in-and-start).

> Piping a script to a shell means running code you have not read. If you would
> rather not, the same install is four commands below — and you can read the
> script first: it is
> [`install.sh`](https://github.com/sevorix/sevorix/blob/main/install.sh) in this
> repository.

---

## 🔧 Manual install

### 1. Download

```bash
VERSION=$(curl -s https://api.github.com/repos/sevorix/sevorix/releases/latest | grep tag_name | cut -d'"' -f4)
curl -LO https://github.com/sevorix/sevorix/releases/download/${VERSION}/sevorix-pro-${VERSION}-x86_64-linux.tar.gz
curl -LO https://github.com/sevorix/sevorix/releases/download/${VERSION}/sevorix-pro-${VERSION}-x86_64-linux.tar.gz.sha256
```

### 2. Verify the download

Not optional. The installer asks for `sudo` and installs a root-owned binary that
every shell command on your machine will be routed through. Check the archive
before you extract it:

```bash
sha256sum -c sevorix-pro-${VERSION}-x86_64-linux.tar.gz.sha256
```

The expected checksum is also printed in the release notes, so you can compare it
against a second source rather than against a file downloaded from the same place
as the archive.

### 3. Install

```bash
tar xzf sevorix-pro-${VERSION}-x86_64-linux.tar.gz
cd sevorix-pro-${VERSION}-x86_64-linux
./install-binary.sh
```

The installer prompts before every privileged step and explains what each one is
for. See [What gets installed where](#-what-gets-installed-where) below.

### 4. Log in and start

```bash
sevorix hub login
sevorix start
sevorix status
```

### 5. Open the Watchtower Dashboard

`sevorix start` prints a session token. Open your local command center:

👉 `http://localhost:3000/dashboard/desktop.html?token=<session-token>`

If you lose the token, `sevorix status` prints it again.

---

## 🏎️ The test drive: see it in action

Don't trust us. Test it. `sevsh` is a secure shell wrapper that routes commands
through the Sevorix engine before they ever reach the processor.

Leave the dashboard open in a browser and run these in your terminal:

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

**Result:** the terminal hangs. Switch to the dashboard — a Yellow intervention
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

---

## 💎 What Pro adds over Lite

| | Lite | Pro |
|---|---|---|
| Shell, network and syscall enforcement | ✅ | ✅ |
| `sevsh`, seccomp interception, agent sandboxing | ✅ | ✅ |
| Watchtower dashboard and live traffic feed | ✅ | ✅ |
| **Jury of Rivals** — ambiguous actions adjudicated by multiple LLMs in consensus | — | ✅ |
| **Prompt-injection classifier** — ML scoring of outbound and inbound content | — | ✅ |
| **Built-in self-protection policies** — controls an agent cannot disable | — | ✅ |
| **Signed receipts** — a cryptographically verifiable audit trail | — | ✅ |
| **JSON hooks** — custom verdict logic from a root-owned directory | — | ✅ |
| **Concurrent sessions** — Lite runs one at a time | 1 | many |
| **Log export** to external sinks | — | ✅ |

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
| `/etc/sudoers.d/sevorix-*` | Passwordless invocation of the helpers above | `root:root` |
| `~/.sevorix/policies`, `~/.sevorix/roles` | Your policy and role definitions | you |
| `~/.local/state/sevorix/` | PID files and session metadata | you |

Every prompt is optional and the installer tells you what is lost by declining.
Run `./install-binary.sh --force` to accept all of them non-interactively.

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

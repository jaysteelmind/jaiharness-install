# jaiharness

Public installer and application downloads for jaiharness, a local agent harness with terminal and browser interfaces.

Latest application: [0.1.0-rc.12](https://github.com/jaysteelmind/jaiharness-install/releases/tag/v0.1.0-rc.12), with PowerPoint and spreadsheet authoring, validation and delivery; richer document previews; helper-model settings; an optional browser team task board; and mouse-wheel scrolling in terminal chat.

Conversations, files, previews and interactive terminals can stay open in docked panels. Plugin catalogs support search and controlled updates. Rich drafts retain quotes and file/folder/session references, and completed turns show file changes and delivered files. Ordinary conversation forks survive deletion of their original conversation. Shared `~/.agents/AGENTS.md` instructions load alongside Jai's own global instructions.

For local workspaces, the shared instruction file also applies on resume; set `JAI_AGENTS_HOME` to a dedicated directory without `AGENTS.md` to exclude it. Deleting an original conversation preserves its full tool-output files until its last dependent conversation is deleted.

In terminal chat, use the wheel to scroll, Shift-drag for text selection where supported, or `/copy` to hold a selectable page. `jaicli --no-mouse` disables mouse capture.

Helpers may use a different reasoning effort on the conversation's model. Choosing other models requires enabling Helper models in Settings; this applies to new conversations.

## Install

Run this command in a terminal:

```sh
curl -fsSL https://jaysteelmind.github.io/jaiharness-install/install.sh | bash
```

The installer downloads verified Node, pnpm, Office Python and application packages for your account, checks application startup, then walks you through choosing a model provider. You do not need Node, Git or a GitHub login beforehand. The initial command requires Bash and curl.

Requires macOS 13.5+ or glibc Linux 2.28+ with kernel 4.18+. Release installation is tested on macOS 15 ARM64 and Ubuntu 24.04 x64/ARM64. The installer also targets Intel Macs, but their Office runtime installation has not been validated for this release. On Windows, use WSL2. Alpine/musl and native Windows are outside this Bash installer. Missing native build tools can be installed with your consent through apt or dnf; macOS may require Apple's Command Line Tools dialog and a retry.

Office authoring downloads a pinned private Python runtime from GitHub release assets and libraries from files.pythonhosted.org. The prepared payload is about 170 MB on macOS ARM64; sizes vary by platform. Preparation is required: a failure stops installation before activation and preserves an existing version. Reinstall or update to add it to an older installation.

Choose a hosted provider or an OpenAI-compatible model server. API keys are hidden while typing; servers without authentication accept an empty key. Setup can send a short model test. Model-server hosting, model weights and optional browser/desktop capabilities have their own requirements.

After setup, open a new terminal and run:

```sh
jaicli
```

`jaicli` opens terminal chat and accepts the same arguments as `jaiharness tui`. If the installer finds an existing shortcut, choose **yes** to back it up and replace it. If you keep that shortcut, use `jaiharness tui` instead. Use `jaiharness` for setup and Host management.

To use a browser on the installation machine, open the address printed by setup. No SSH command is needed. Find the current browser address at any time with:

```sh
jaiharness host status
```

The shared Host keeps running after setup. Stop it with `jaiharness host stop`; its address may change the next time it starts.

## Remote browser

Only use an SSH tunnel when jaiharness and your browser are on **different computers**. Terminal chat on the installation machine works without a tunnel.

1. Run `jaiharness host status` on the installation machine and note its port.
2. On the computer where you want to open the browser, open another terminal. Use the optional SSH command printed by setup, or replace `HOST_PORT` and `user@installation-machine` below:

   ```sh
   ssh -N -L 13080:127.0.0.1:HOST_PORT user@installation-machine
   ```

3. Open http://127.0.0.1:13080 in the browser on that computer. Keep the SSH terminal open while using it.

Use your normal SSH login for the installation machine. If SSH reports a refused connection, check that address and SSH service; you can still chat with `jaicli` on the installation machine.

## Options and updates

If you already installed and `jaicli` is missing, run:

```sh
curl -fsSL https://jaysteelmind.github.io/jaiharness-install/install.sh | bash -s -- --repair-commands
```

Then open a new terminal and run `jaicli`, or use `~/.local/bin/jaicli` immediately. Repair adds the launch commands without downloading the application, restarting the Host or changing your settings. It requires an existing complete installation. An existing `jaicli` prompts for replacement. To back it up and replace it without a prompt, including an old shortcut that connects to the wrong Host, run:

```sh
curl -fsSL https://jaysteelmind.github.io/jaiharness-install/install.sh | bash -s -- --repair-commands --replace-jaicli
```

The original file or symlink is saved in `~/.local/share/jaiharness/backups/`; a symlink's target is untouched. Without replacement consent, normal installation keeps the shortcut and prints a `jaiharness tui` fallback; command repair exits with an error.

For unattended software installation without model setup or shell-file changes:

```sh
curl -fsSL https://jaysteelmind.github.io/jaiharness-install/install.sh | bash -s -- --skip-setup --no-modify-path
```

Run `~/.local/bin/jaiharness setup` later to configure the model. `--install-system-deps` permits installation of missing system packages when needed; sudo may still ask for a password.

Stop the Host with its existing launcher before rerunning the installer to update or repair the application. Settings and credentials are preserved. Installed software lives under `~/.local/share/jaiharness`; the commands are `~/.local/bin/jaiharness` and `~/.local/bin/jaicli`. User data lives separately in `~/.jai`, or `JAI_HOME` when configured.

Old versions and failed-attempt diagnostics remain available and can use about 1 GB per attempt. Remove unwanted versions only after confirming their processes have stopped. An uncatchable interruption can leave `.install-lock`; inspect its PID before removing the stale lock. The installer refuses unrelated management commands and requires consent to replace an existing chat shortcut. If setup reports that an existing data home needs adoption, stop its legacy Host processes, run `jaiharness tui --adopt-home` once, then rerun `jaiharness setup`. The installed application is retained when setup cannot finish.

## Downloads and verification

The [releases](https://github.com/jaysteelmind/jaiharness-install/releases) contain the application archive, installer and checksums. Each installer embeds the exact application SHA-256 plus the Node and pnpm integrity values; it verifies downloads before use. Release candidates are marked as prereleases. The archive includes its license and third-party notices.

This repository contains distribution files. The development repository remains separately managed.

# jaiharness

Public installer and application downloads for jaiharness, a local agent harness with terminal and browser interfaces.

## Install

Run this command in a terminal:

```sh
curl -fsSL https://jaysteelmind.github.io/jaiharness-install/install.sh | bash
```

The installer downloads verified Node, pnpm and application packages for your account, checks application startup, then walks you through choosing a model provider. You do not need Node, Git or a GitHub login beforehand. The initial command requires Bash and curl.

Supported systems are macOS 13.5+ and glibc Linux 2.28+ with kernel 4.18+, on x64 or ARM64. On Windows, use WSL2. Alpine/musl and native Windows are outside this Bash installer. Missing native build tools can be installed with your consent through apt or dnf; macOS may require Apple's Command Line Tools dialog and a retry.

Choose a hosted provider or an OpenAI-compatible model server. API keys are hidden while typing; servers without authentication accept an empty key. Setup can send a short model test. Model-server hosting, model weights and optional browser/desktop capabilities have their own requirements.

After setup, open a new terminal and run:

```sh
jaicli
```

`jaicli` opens terminal chat and accepts the same arguments as `jaiharness tui`. Use `jaiharness` for setup and Host management. Setup also prints the browser address. On a remote machine, use the printed SSH forwarding example. The shared Host keeps running until you stop it with `jaiharness host stop`.

## Options and updates

If you already installed and `jaicli` is missing, run:

```sh
curl -fsSL https://jaysteelmind.github.io/jaiharness-install/install.sh | bash -s -- --repair-commands
```

Then open a new terminal and run `jaicli`, or use `~/.local/bin/jaicli` immediately. Repair adds the launch commands without downloading the application, restarting the Host or changing your settings. It requires an existing complete installation. An unrelated `jaicli` is preserved: normal installation prints a notice and continues; command repair exits with an error. Use `jaiharness tui` when keeping that command.

For unattended software installation without model setup or shell-file changes:

```sh
curl -fsSL https://jaysteelmind.github.io/jaiharness-install/install.sh | bash -s -- --skip-setup --no-modify-path
```

Run `~/.local/bin/jaiharness setup` later to configure the model. `--install-system-deps` permits installation of missing system packages when needed; sudo may still ask for a password.

Stop the Host with its existing launcher before rerunning the installer to update or repair the application. Settings and credentials are preserved. Installed software lives under `~/.local/share/jaiharness`; the commands are `~/.local/bin/jaiharness` and `~/.local/bin/jaicli`. User data lives separately in `~/.jai`, or `JAI_HOME` when configured.

Old versions and failed-attempt diagnostics remain available and can use about 1 GB per attempt. Remove unwanted versions only after confirming their processes have stopped. An uncatchable interruption can leave `.install-lock`; inspect its PID before removing the stale lock. The installer refuses unrelated command paths. If setup reports that an existing data home needs adoption, stop its legacy Host processes, run `jaiharness tui --adopt-home` once, then rerun `jaiharness setup`. The installed application is retained when setup cannot finish.

## Downloads and verification

The [releases](https://github.com/jaysteelmind/jaiharness-install/releases) contain the application archive, installer and checksums. Each installer embeds the exact application SHA-256 plus the Node and pnpm integrity values; it verifies downloads before use. Release candidates are marked as prereleases. The archive includes its license and third-party notices.

This repository contains distribution files. The development repository remains separately managed.

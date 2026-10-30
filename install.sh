#!/usr/bin/env bash
# Release preparation embeds the archive URL and digest. Keep main last so a truncated pipe cannot install.

fail() { printf '\nInstallation stopped: %s\n' "$*" >&2; exit 1; }
say() { printf '\n==> %s\n' "$*"; }

download() {
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --connect-timeout 20 --max-time 900 --retry 2 --output "$2" "$1" </dev/null
}

check_sha256() {
  local actual
  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$1")
  else
    actual=$(shasum -a 256 "$1")
  fi
  [ "${actual%% *}" = "$2" ] || fail "Checksum mismatch for ${1##*/}; no downloaded code was run."
}

at_least() {
  local major=${1%%.*} rest=${1#*.} minimum_major=$2 minimum_minor=$3
  local minor=${rest%%.*}
  [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1
  [ "$major" -gt "$minimum_major" ] || { [ "$major" -eq "$minimum_major" ] && [ "$minor" -ge "$minimum_minor" ]; }
}

platform() {
  case $(uname -s) in
    Darwin)
      os=darwin
      at_least "$(sw_vers -productVersion)" 13 5 || fail 'macOS 13.5 or later is required.'
      ;;
    Linux)
      os=linux
      local libc
      libc=$(getconf GNU_LIBC_VERSION 2>/dev/null) || fail 'This installer requires glibc Linux; Alpine/musl is not supported.'
      at_least "${libc##* }" 2 28 || fail 'glibc 2.28 or later is required.'
      at_least "$(uname -r)" 4 18 || fail 'Linux kernel 4.18 or later is required.'
      ;;
    *) fail 'Use Linux or macOS. On Windows, run this command inside WSL2.' ;;
  esac
  case $(uname -m) in
    x86_64|amd64) arch=x64 ;;
    arm64|aarch64) arch=arm64 ;;
    *) fail 'Only 64-bit Intel/AMD and ARM64 systems are supported.' ;;
  esac
  if [ "$os" = darwin ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ]; then arch=arm64; fi
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

system_tools() {
  local reply
  if [ "$install_system_deps" != yes ]; then
    [ "$terminal" = yes ] || fail 'System build tools are missing. Rerun with --install-system-deps to install them.'
    printf 'Install missing system tools using your OS package manager? [y/N] ' >/dev/tty
    IFS= read -r reply </dev/tty || fail 'No answer received.'
    case "$reply" in y|Y|yes|YES) ;; *) fail 'System tools were not installed.' ;; esac
  fi
  if [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 || fail 'sudo is required to install system packages.'
  fi
  if [ "$os" = darwin ]; then
    xcode-select --install || fail 'Install the Xcode Command Line Tools, then rerun this installer.'
    fail 'Complete the Apple Command Line Tools dialog, then rerun this installer. Your existing installation is unchanged.'
  elif command -v apt-get >/dev/null 2>&1; then
    as_root apt-get update </dev/null || fail 'apt-get update failed; correct its error and retry.'
    as_root apt-get install -y build-essential python3 ca-certificates curl tar gzip coreutils </dev/null || fail 'System package installation failed.'
  elif command -v dnf >/dev/null 2>&1; then
    as_root dnf install -y gcc-c++ make python3 ca-certificates curl tar gzip coreutils </dev/null || fail 'System package installation failed.'
  else
    fail 'Install Python 3, a C/C++ compiler, make, tar, gzip and a SHA-256 utility with your OS package manager, then rerun.'
  fi
}

cleanup() {
  local status=$?
  trap - EXIT
  if [ "$locked" = yes ]; then
    rm "$prefix/.install-lock/pid"
    rmdir "$prefix/.install-lock"
  fi
  if [ "$status" -ne 0 ] && [ -n "$candidate" ]; then
    if [ "${repair_commands:-no}" = yes ]; then
      printf 'Command repair did not complete; resolve the error above and rerun with --repair-commands.\n' >&2
    elif [ "$installed" = yes ]; then
      printf 'jaiharness is installed; setup or shell configuration is incomplete. Run: %s setup\n' "$command_path" >&2
    else
      printf 'Installation files and diagnostics retained at: %s\n' "$candidate" >&2
    fi
  fi
  exit "$status"
}

npm_install() {
  # Explicit flags override inherited npm policies that would omit native runtime requirements.
  "$candidate/node/bin/node" "$candidate/node/lib/node_modules/npm/bin/npm-cli.js" install \
    --global=false --prefix "$candidate/app" --ignore-scripts=false --include=optional --include=prod \
    --workspaces=false --dry-run=false --bin-links=true --no-audit --no-fund "$candidate/downloads/jaiharness.tgz" </dev/null
}

write_launcher() {
  mkdir -p "$candidate/bin"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'install_dir=%q\n' "$candidate"
    printf 'export JAI_PRIMARY_RUNTIME="${JAI_PRIMARY_RUNTIME-$install_dir/resources/primary-runtime}"\n'
    printf 'export PATH="$PATH:$install_dir/node/bin:$install_dir/tools/bin"\n'
    printf 'exec "$install_dir/node/bin/node" "$install_dir/app/node_modules/@jaysteelmind/jaiharness/bin/jaiharness.mjs" "$@"\n'
  } >"$candidate/bin/jaiharness"
  chmod 755 "$candidate/bin/jaiharness"
}

smoke() {
  "$candidate/node/bin/node" --input-type=module - "$candidate" <<'NODE'
import { spawnSync } from 'node:child_process';
import { mkdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';
const dir = process.argv[2];
const home = join(dir, 'smoke-home');
mkdirSync(home, { mode: 0o700 });
const env = { HOME: home, JAI_HOME: join(home, '.jai'), PATH: `${dir}/node/bin:/usr/bin:/bin`, LANG: 'en_US.UTF-8' };
const bin = join(dir, 'app/node_modules/@jaysteelmind/jaiharness/bin/jaiharness.mjs');
const run = args => spawnSync(process.execPath, [bin, ...args], { env, cwd: home, encoding: 'utf8', timeout: 60000 });
const boot = run(['tui', '--once']);
const stop = run(['host', 'stop']);
if (boot.status !== 0 || stop.status !== 0) {
  process.stderr.write(`${boot.stdout || ''}${boot.stderr || ''}${stop.stdout || ''}${stop.stderr || ''}`);
  throw new Error('Installed application startup/shutdown check failed; the previous installation was not replaced.');
}
rmSync(home, { recursive: true });
NODE
}

publish_install() {
  "$candidate/node/bin/node" --input-type=module - "$prefix" "$candidate" "$command_path" "$chat_path" "$repair_commands" "$chat_available" <<'NODE'
import { chmodSync, constants, copyFileSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, realpathSync, renameSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { basename, join } from 'node:path';
const [root, candidate, command, chat, repair, chatAvailable] = process.argv.slice(2);
function exists(path) { try { return lstatSync(path); } catch (e) { if (e.code === 'ENOENT') return null; throw e; } }
const replacingChat = chatAvailable === 'replace';
const oldChat = exists(chat);
if (replacingChat && (!oldChat || !(oldChat.isFile() || oldChat.isSymbolicLink()))) {
  throw new Error(`Refusing to replace a missing command or directory: ${chat}`);
}
const commands = [[command, join(root, 'current/bin/jaiharness')]];
if (chatAvailable !== 'no') commands.push([chat, join(root, 'bin/jaicli')]);
for (const [path, target] of commands) {
  const entry = exists(path);
  if (entry && !(replacingChat && path === chat) && (!entry.isSymbolicLink() || readlinkSync(path) !== target)) throw new Error(`Refusing to replace ${path}`);
}
const current = join(root, 'current');
const previous = exists(current);
if (previous && !previous.isSymbolicLink()) throw new Error(`Refusing to replace ${current}`);
if (repair === 'yes' && (!previous || realpathSync(current) !== candidate)) throw new Error('The active installation changed; retry command repair.');
if (chatAvailable !== 'no') {
  mkdirSync(join(root, 'bin'), { recursive: true });
  const launcher = join(root, 'bin/jaicli');
  const quote = value => `'${value.replaceAll("'", "'\\''")}'`;
  const script = `#!/usr/bin/env bash\nexec ${quote(join(root, 'current/bin/jaiharness'))} tui "$@"\n`;
  if (!exists(launcher) || readFileSync(launcher, 'utf8') !== script) {
    const next = `${launcher}.next-${process.pid}`;
    writeFileSync(next, script, { mode: 0o755, flag: 'wx' });
    try { renameSync(next, launcher); } finally { if (exists(next)) unlinkSync(next); }
  }
  chmodSync(launcher, 0o755);
}
const pending = join(root, `.current-next-${basename(candidate)}`);
const created = [];
let backup;
let replacedChat = false;
let createdPendingChat = false;
const pendingChat = `${chat}.next-${process.pid}`;
if (repair !== 'yes') symlinkSync(candidate, pending);
try {
  if (replacingChat) {
    mkdirSync(join(root, 'backups'), { recursive: true });
    backup = join(mkdtempSync(join(root, 'backups/jaicli-')), 'jaicli');
    if (oldChat.isSymbolicLink()) symlinkSync(readlinkSync(chat), backup);
    else copyFileSync(chat, backup, constants.COPYFILE_EXCL);
    symlinkSync(join(root, 'bin/jaicli'), pendingChat);
    createdPendingChat = true;
    const latest = exists(chat);
    if (!latest || latest.ino !== oldChat.ino || latest.dev !== oldChat.dev || latest.mtimeMs !== oldChat.mtimeMs) {
      throw new Error('The jaicli command changed during installation; retry.');
    }
    renameSync(pendingChat, chat);
    replacedChat = true;
  }
  for (const [path, target] of commands) {
    if (!exists(path)) { symlinkSync(target, path); created.push([path, target]); }
  }
  if (repair !== 'yes') renameSync(pending, current);
} catch (error) {
  if (repair !== 'yes' && exists(pending)) unlinkSync(pending);
  for (const [path, target] of created) {
    if (exists(path)?.isSymbolicLink() && readlinkSync(path) === target) unlinkSync(path);
  }
  if (createdPendingChat && exists(pendingChat)) unlinkSync(pendingChat);
  if (replacedChat && exists(chat)?.isSymbolicLink() && readlinkSync(chat) === join(root, 'bin/jaicli')) renameSync(backup, chat);
  throw error;
}
if (backup) console.log(`Previous jaicli shortcut saved to ${backup}`);
NODE
}

configure_path() {
  [ "$modify_path" = yes ] || return 0
  local rc
  for rc in "$HOME/.profile" "$HOME/.bashrc" "${ZDOTDIR:-$HOME}/.zshrc" "$HOME/.bash_profile" "$HOME/.bash_login"; do
    case "$rc" in */.bash_profile|*/.bash_login) [ -f "$rc" ] || continue ;; esac
    if ! grep -Fq '# jaiharness command path' "$rc" 2>/dev/null; then
      printf '\n# jaiharness command path\nexport PATH="$HOME/.local/bin:$PATH"\n' >>"$rc"
    fi
  done
}

main() {
  set -euo pipefail
  local caller_umask caller_path=$PATH
  caller_umask=$(umask)
  umask 077
  local archive_url='https://github.com/jaysteelmind/jaiharness-install/releases/download/v0.1.0-rc.12/jaysteelmind-jaiharness-0.1.0-rc.12.tgz'
  local archive_hash='341fc3ebdfb3a770dc8a3ddd409e3ef88ecfe67dd85ae1759797979590374ab9'
  local release_version='0.1.0-rc.12'
  local node_version=v24.22.1
  # Bash 5 can unwind main's locals before its EXIT trap after a failed command.
  prefix="${JAI_INSTALL_DIR:-$HOME/.local/share/jaiharness}" candidate='' locked=no installed=no
  command_path="$HOME/.local/bin/jaiharness" repair_commands=no
  local chat_path="$HOME/.local/bin/jaicli" chat_available=yes replace_jaicli=no
  local terminal=no modify_path=yes skip_setup=no install_system_deps=no start_dir=$PWD
  local os arch node_hash node_archive reply
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --skip-setup) skip_setup=yes ;;
      --no-modify-path) modify_path=no ;;
      --install-system-deps) install_system_deps=yes ;;
      --repair-commands) repair_commands=yes ;;
      --replace-jaicli) replace_jaicli=yes ;;
      --help|-h)
        printf 'Usage: bash install.sh [--skip-setup] [--no-modify-path] [--install-system-deps] [--repair-commands] [--replace-jaicli]\nInstalls jaiharness and jaicli for your account; --repair-commands repairs existing launch commands without downloading or restarting. --replace-jaicli backs up and replaces an existing chat command. JAI_INSTALL_DIR overrides the installation directory.\n'
        return ;;
      *) fail "Unknown option: $1" ;;
    esac
    shift
  done
  [[ "$archive_hash" =~ ^[a-f0-9]{64}$ ]] || fail 'This is an installer template. Use the installer emitted for a release.'
  case "$prefix" in /*) ;; *) fail 'JAI_INSTALL_DIR must be an absolute path.' ;; esac
  [ "$prefix" != / ] && [ "$prefix" != "$HOME" ] || fail 'Choose a dedicated installation directory.'
  platform
  if ( : </dev/tty ) 2>/dev/null; then terminal=yes; fi
  if [ "$repair_commands" = no ]; then
    for utility in curl tar gzip; do
      command -v "$utility" >/dev/null 2>&1 || system_tools
      command -v "$utility" >/dev/null 2>&1 || fail "Required command is unavailable: $utility"
    done
    if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then system_tools; fi
  fi
  [ ! -L "$prefix" ] || fail 'The installation directory must not be a symbolic link.'
  if [ -e "$prefix" ]; then
    [ -f "$prefix/.jaiharness-installer" ] && [ "$(cat "$prefix/.jaiharness-installer")" = 1 ] \
      || fail "Refusing to adopt an unrelated directory: $prefix"
  else
    [ "$repair_commands" = no ] || fail 'No installer-owned installation exists. Run the installer without --repair-commands first.'
    mkdir -p "$prefix"
    printf '1\n' >"$prefix/.jaiharness-installer"
  fi
  mkdir "$prefix/.install-lock" 2>/dev/null || fail "Installer lock exists (PID $(cat "$prefix/.install-lock/pid" 2>/dev/null || printf unknown)). Check that process before removing $prefix/.install-lock and retrying."
  printf '%s\n' "$$" >"$prefix/.install-lock/pid"
  locked=yes
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  if [ -e "$command_path" ] || [ -L "$command_path" ]; then
    [ -L "$command_path" ] && [ "$(readlink "$command_path")" = "$prefix/current/bin/jaiharness" ] \
      || fail "An unrelated command already exists: $command_path"
  fi
  if { [ -e "$chat_path" ] || [ -L "$chat_path" ]; } \
    && { [ ! -L "$chat_path" ] || [ "$(readlink "$chat_path")" != "$prefix/bin/jaicli" ]; }; then
    [ ! -d "$chat_path" ] || [ -L "$chat_path" ] || fail "The chat command path is a directory: $chat_path"
    if [ "$replace_jaicli" = no ] && [ "$terminal" = yes ]; then
      printf 'An existing chat command is at %s.\nBack it up and replace it with jaiharness chat? [y/N] ' "$chat_path" >/dev/tty
      read -r reply </dev/tty || reply=''
      case "$reply" in y|Y|yes|YES) replace_jaicli=yes ;; esac
    fi
    if [ "$replace_jaicli" = yes ]; then
      chat_available=replace
    else
      [ "$repair_commands" = no ] || fail "An unrelated command already exists: $chat_path. Use jaiharness tui, or rerun with --repair-commands --replace-jaicli to back it up and replace it."
      printf 'jaicli already exists and was left unchanged; use jaiharness tui.\n'
      chat_available=no
    fi
  fi
  mkdir -p "$prefix/versions" "$HOME/.local/bin"
  if [ "$repair_commands" = yes ]; then
    [ -L "$prefix/current" ] || fail 'No active installer-owned version exists. Run the full installer first.'
    candidate=$(cd "$prefix/current" && pwd -P) || fail 'The active installation directory is unavailable.'
    local versions
    versions=$(cd "$prefix/versions" && pwd -P)
    [ "${candidate%/*}" = "$versions" ] && [ -x "$candidate/node/bin/node" ] && [ -x "$candidate/bin/jaiharness" ] \
      || fail 'The active version is not a complete installer-owned installation. Run the full installer to repair it.'
    installed=yes
    publish_install
    umask "$caller_umask"
    configure_path
    printf 'Commands repaired.\nChat command: %s\n' "$chat_path"
    case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) printf 'Open a new terminal to use jaicli by name.\n' ;; esac
    cleanup
  fi
  candidate=$(mktemp -d "$prefix/versions/$release_version.XXXXXXXX")
  mkdir "$candidate/downloads" "$candidate/node"
  printf '{"private":true}\n' >"$candidate/package.json"
  cd "$candidate"
  case "$os-$arch" in
    darwin-arm64) node_hash=89c682593d76cd44233fa53b1563264e7de9cbb189cad169135c5b4fadfbc0a7 ;;
    darwin-x64) node_hash=d132557e7ee2b85af08b0c8c34338e65c6430f2238d01f727728ef42dc83b035 ;;
    linux-arm64) node_hash=33c37be234ba8bee041961047b19160f4d7d0f164e8e246f78bdd10feff148b3 ;;
    linux-x64) node_hash=eb6728e77c576a35162c122c45ccadf224d89ff00abc8dae46cc2897c6002d7c ;;
  esac
  node_archive="node-$node_version-$os-$arch.tar.gz"
  say "Installing private Node $node_version ($os/$arch)"
  download "https://nodejs.org/dist/$node_version/$node_archive" "$candidate/downloads/node.tar.gz"
  check_sha256 "$candidate/downloads/node.tar.gz" "$node_hash"
  tar -xzf "$candidate/downloads/node.tar.gz" -C "$candidate/node" --strip-components=1
  "$candidate/node/bin/node" --version || fail 'The downloaded Node runtime cannot run on this system.'
  export PATH="$candidate/node/bin:$PATH"
  say 'Installing pnpm 11.7.0 for plugin management'
  download 'https://registry.npmjs.org/pnpm/-/pnpm-11.7.0.tgz' "$candidate/downloads/pnpm.tgz"
  "$candidate/node/bin/node" --input-type=module - "$candidate/downloads/pnpm.tgz" <<'NODE'
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
const hash = createHash('sha512').update(readFileSync(process.argv[2])).digest('base64');
if (hash !== 'GcyFLBIMcSV2DyRD7mvgyltA+fUFmN4aCaHxd1A+AQ5Xwjx3ZG4B52HeWb+HT7IqM5jDOrlpH8E+uUa28PTWIA==') throw new Error('pnpm checksum mismatch');
NODE
  mkdir -p "$candidate/tools/pnpm" "$candidate/tools/bin"
  tar -xzf "$candidate/downloads/pnpm.tgz" -C "$candidate/tools/pnpm" --strip-components=1
  chmod 755 "$candidate/tools/pnpm/bin/pnpm.cjs"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'node_dir=%q\n' "$candidate/node/bin"
    printf 'export PATH="$node_dir:$PATH"\n'
    printf 'exec %q %q "$@"\n' "$candidate/node/bin/node" "$candidate/tools/pnpm/bin/pnpm.cjs"
  } >"$candidate/tools/bin/pnpm"
  chmod 755 "$candidate/tools/bin/pnpm"
  [ "$("$candidate/tools/bin/pnpm" --version)" = 11.7.0 ] || fail 'The installed pnpm version could not be verified.'
  say "Installing jaiharness $release_version"
  download "$archive_url" "$candidate/downloads/jaiharness.tgz"
  check_sha256 "$candidate/downloads/jaiharness.tgz" "$archive_hash"
  if ! npm_install >"$candidate/install.log" 2>&1; then
    tail -n 35 "$candidate/install.log" >&2
    if grep -Eq 'gyp ERR!|make:.*not found|[Cc]ompiler.*not found' "$candidate/install.log" \
      && { ! command -v python3 >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1 || ! command -v c++ >/dev/null 2>&1; }; then
      system_tools
      npm_install >>"$candidate/install.log" 2>&1 || { tail -n 35 "$candidate/install.log" >&2; fail 'npm installation failed; see install.log above.'; }
    else
      fail 'npm could not install the runtime dependencies. See install.log above; network failures may include the ripgrep binary download from GitHub. Retrying is safe.'
    fi
  fi
  say 'Installing private Python and Office authoring libraries'
  "$candidate/node/bin/node" "$candidate/app/node_modules/@jaysteelmind/jaiharness/node_modules/@jai-ai/jai-tool-workspace-dependencies/lib/prepare-office.js" \
    --output "$candidate/resources" --cache "$candidate/downloads/office" \
    >>"$candidate/install.log" 2>&1 || { tail -n 35 "$candidate/install.log" >&2; fail 'Office runtime preparation failed; the previous installation remains active.'; }
  write_launcher
  say 'Checking the installed application'
  smoke >>"$candidate/install.log" 2>&1 || { tail -n 35 "$candidate/install.log" >&2; fail 'Application verification failed.'; }
  export PATH="$caller_path"
  umask "$caller_umask"
  local host_status
  host_status=$("$candidate/bin/jaiharness" host status) || fail 'The current data home cannot be used by this installation. Stop its existing Host using that installation, or resolve the diagnostic above, then retry.'
  [ "$host_status" = 'jai host: no managed host' ] || fail 'A Jai host is running. Stop it with its own launcher when its work is finished, then rerun.'
  publish_install
  installed=yes
  configure_path
  cd "$start_dir"
  say "jaiharness $release_version installed"
  printf 'Command: %s\n' "$command_path"
  if [ "$chat_available" != no ]; then printf 'Chat command: %s\n' "$chat_path"; fi
  local resolved_command
  resolved_command=$(command -v jaiharness || true)
  if [ -n "$resolved_command" ] && [ "$resolved_command" != "$command_path" ]; then
    printf 'This shell currently finds %s first. Use the command path above or open a new terminal.\n' "$resolved_command"
  fi
  if [ "$skip_setup" = no ] && [ "$terminal" = yes ]; then
    "$command_path" setup </dev/tty >/dev/tty
  else
    printf 'Model setup is pending. Run: %s setup\n' "$command_path"
  fi
  if [ "$chat_available" = no ]; then
    printf '\nYour existing jaicli was kept. Start chatting with: %s tui\n' "$command_path"
    printf 'To back up and replace that shortcut:\ncurl -fsSL https://jaysteelmind.github.io/jaiharness-install/install.sh | bash -s -- --repair-commands --replace-jaicli\n'
  fi
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) printf 'Open a new terminal to use the jaiharness command by name.\n' ;; esac
  cleanup
}

main "$@"

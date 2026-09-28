#!/usr/bin/env bash
# GEWA digihub — fresh Ubuntu VM bootstrap.
#
# Gets a brand-new Ubuntu VM from "no git, no SSH key" to "private DevOps
# repo cloned and setup.sh running". Bootstraps the chicken-and-egg around
# cloning a private repo before GitHub auth is configured (see issue #60).
#
# The public mirror of this script lives at
#   https://github.com/GEWA-codecrushers/devops-bootstrap
# which is what `curl | bash` fetches. The canonical copy is this file in
# the DevOps repo; sync after editing (see scripts/setup/ubuntu/README.md).
#
# Usage on a fresh VM:
#   curl -fsSL https://raw.githubusercontent.com/GEWA-codecrushers/devops-bootstrap/main/bootstrap.sh | bash
# Arguments are passed on to setup.sh, e.g. raw apt/mise output:
#   curl -fsSL …/bootstrap.sh | bash -s -- --verbose
#
# Standalone on purpose: it runs before the repo (and scripts/lib/ui.sh) is
# on disk, so the output helpers below are a small inline copy of ui.sh.

set -e
set -o pipefail

LOG="${XDG_STATE_HOME:-$HOME/.local/state}/devops/bootstrap.log"
REPO_SSH="git@github.com:GEWA-codecrushers/DevOps.git"
REPO_DIR="${DEVOPS_REPO:-$HOME/repo/DevOps}"
SSH_KEY="$HOME/.ssh/id_ed25519"
VERBOSE=0
case " $* " in *" --verbose "*|*" -v "*) VERBOSE=1 ;; esac

# ── Output (inline copy of scripts/lib/ui.sh basics) ───────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != dumb ]; then
  C_RESET=$'\033[0m' C_BOLD=$'\033[1m' C_DIM=$'\033[2m'
  C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_BLUE=$'\033[34m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE=''
fi
section() { printf '\n%s▸ %s[%s]%s%s %s%s\n' "$C_BOLD$C_BLUE" "$C_DIM" "$2" "$C_RESET" "$C_BOLD$C_BLUE" "$1" "$C_RESET"; }
info()    { printf '  %s\n' "$*"; }
dim()     { printf '  %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
ok()      { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()    { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()     { printf '  %s✗ %s%s\n' "$C_RED" "$*" "$C_RESET"; }

# Run a noisy command with its output in $LOG (raw with --verbose);
# on failure show its last lines. stdin is /dev/null — see the ssh note below.
quiet() {
  local label=$1 from rc=0; shift
  printf '\n── %s\n$ %s\n' "$label" "$*" >>"$LOG"
  from=$(( $(wc -l <"$LOG") + 1 ))
  if [ "$VERBOSE" = 1 ]; then
    "$@" </dev/null 2>&1 | tee -a "$LOG" || rc=$?
  else
    "$@" >>"$LOG" 2>&1 </dev/null || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then ok "$label"; return 0; fi
  err "$label failed (exit $rc)"
  if [ "$VERBOSE" != 1 ]; then tail -n "+$from" "$LOG" | tail -n 15 | sed 's/^/    │ /' || true; fi
  return "$rc"
}

on_abort() {
  local rc=$?
  printf '\n%s\n' "${C_BOLD}${C_RED}bootstrap aborted (exit $rc)${C_RESET}"
  info "Log:   $LOG"
  info "Retry: curl -fsSL https://raw.githubusercontent.com/GEWA-codecrushers/devops-bootstrap/main/bootstrap.sh | bash"
  dim "Re-running is safe: the SSH key and the clone are reused."
  exit "$rc"
}
trap on_abort ERR
trap 'printf "\n"; err "Stopped (Ctrl-C)"; exit 130' INT

# Read from the controlling terminal so prompts work under `curl ... | bash`
# (where stdin is the piped script, not the keyboard). Drains any buffered
# keystrokes first so a stray Enter from the previous step (e.g. while
# apt-get was running) doesn't get auto-consumed and skip past the prompt.
read_tty() {
  local var="$1" prompt="$2"
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    err "No controlling terminal — re-run from an interactive shell"
    exit 1
  fi
  while read -r -t 0.05 -n 4096 _drain </dev/tty 2>/dev/null; do :; done
  printf '  %s' "$prompt" >/dev/tty
  IFS= read -r "$var" </dev/tty
}

# `ssh -T git@github.com` ALWAYS exits 1 even on successful auth — GitHub
# replies "Hi <user>! You've successfully authenticated, but GitHub does
# not provide shell access." and closes with status 1. The `|| true` keeps
# `set -e` from killing the script on that expected non-zero exit; the
# real success/failure decision is made by grepping the output.
#
# `</dev/null` is critical under `curl | bash`: ssh inherits stdin from
# bash (which is the script pipe), and would otherwise consume the rest
# of the script and forward it to GitHub. Bash then hits EOF on the next
# line read and exits cleanly with code 0 — the exact "silent exit" bug
# from issue #60. The same applies to git, apt-get and anything else that
# might read stdin.
github_auth() {
  SSH_OUTPUT=$(ssh -T \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=accept-new \
    git@github.com </dev/null 2>&1 || true)
  printf '%s' "$SSH_OUTPUT" | grep -q "successfully authenticated"
}

if [ "$(id -u)" -eq 0 ]; then
  echo "Script can't run as root | Script kann nicht als Root ausgeführt werden"
  exit 1
fi

mkdir -p "${LOG%/*}"
printf '# %s — bootstrap.sh\n' "$(date '+%Y-%m-%d %H:%M:%S')" >"$LOG"
. /etc/os-release 2>/dev/null || true
printf '%s  %s\n' "${C_BOLD}DevOps VM bootstrap${C_RESET}" "${C_DIM}$(hostname) · ${PRETTY_NAME:-Linux}${C_RESET}"
dim "Installs git, sets up a GitHub SSH key, clones the DevOps repo, then runs setup.sh."

section "Prerequisites" 1/4
if ! timeout 5 curl -fsS -o /dev/null https://github.com 2>/dev/null; then
  err "Cannot reach github.com — check the VM's network connection"
  exit 1
fi
ok "Network: github.com reachable"
MISSING=()
for pkg in git openssh-client curl ca-certificates; do
  dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" || MISSING+=("$pkg")
done
if [ ${#MISSING[@]} -eq 0 ]; then
  ok "git, ssh, curl already installed"
else
  sudo -n true 2>/dev/null || { info "sudo password needed (apt)"; sudo -v; }
  quiet "apt package lists" sudo apt-get update -q
  quiet "apt install ${MISSING[*]}" sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -q "${MISSING[@]}"
fi

section "SSH key" 2/4
if [ -f "$SSH_KEY" ]; then
  ok "Reusing $SSH_KEY"
else
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  SSH_EMAIL=""
  until [[ "$SSH_EMAIL" == ?*@?*.?* ]]; do
    [ -n "$SSH_EMAIL" ] && warn "'$SSH_EMAIL' doesn't look like an email address"
    read_tty SSH_EMAIL "Email for the new SSH key (your GitHub email): "
  done
  ssh-keygen -q -t ed25519 -C "$SSH_EMAIL" -f "$SSH_KEY" -N "" </dev/null
  ok "Created $SSH_KEY"
fi

section "GitHub access" 3/4
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
if ! grep -q "^github.com " "$HOME/.ssh/known_hosts" 2>/dev/null; then
  ssh-keyscan -T 5 -t ed25519,rsa,ecdsa github.com 2>/dev/null >> "$HOME/.ssh/known_hosts" \
    || dim "ssh-keyscan didn't add a host key; relying on accept-new"
fi
# Re-runs: the key is usually registered already — skip the copy-paste step
if github_auth; then
  ok "GitHub accepts the key — $(printf '%s' "$SSH_OUTPUT" | grep -o 'Hi [^!]*')"
else
  info "Add this public key to GitHub: ${C_BOLD}https://github.com/settings/ssh/new${C_RESET}"
  dim "Title: e.g. \"$(hostname) VM\" · Key type: Authentication Key · Key: the whole line below"
  printf '\n    %s\n\n' "$(cat "$SSH_KEY.pub")"
  # Retry until it works — a key pasted a second too late shouldn't abort the bootstrap
  while true; do
    read_tty REPLY "Press Enter once the key is added (q to quit)... "
    if [[ "$REPLY" == [qQ]* ]]; then err "Stopped — re-run once the key is on GitHub"; exit 1; fi
    if github_auth; then break; fi
    warn "GitHub doesn't accept the key yet. ssh said:"
    printf '%s\n' "$SSH_OUTPUT" | sed 's/^/    │ /'
    dim "Common causes: key not saved on github.com/settings/ssh yet · wrong line copied · outbound port 22 blocked"
  done
  ok "GitHub accepts the key — $(printf '%s' "$SSH_OUTPUT" | grep -o 'Hi [^!]*')"
fi

section "DevOps repo" 4/4
mkdir -p "$(dirname "$REPO_DIR")"
if [ -d "$REPO_DIR/.git" ]; then
  quiet "Pulled latest into $REPO_DIR" git -C "$REPO_DIR" pull --ff-only
elif [ -e "$REPO_DIR" ]; then
  err "$REPO_DIR exists but is not a git repo — move it aside and re-run"
  exit 1
else
  quiet "Cloned to $REPO_DIR" git clone "$REPO_SSH" "$REPO_DIR"
fi

printf '\n%s\n' "${C_BOLD}${C_GREEN}Bootstrap done — handing off to setup.sh${C_RESET}"
dim "Log: $LOG"
echo
exec bash "$REPO_DIR/scripts/setup/ubuntu/setup.sh" "$@"

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

set -e
trap 'echo "..Stopping....."; exit' INT

if [ "$(id -u)" -eq 0 ]; then
  echo "Script can't run as root | Script kann nicht als Root ausgeführt werden"
  exit 1
fi

REPO_SSH="git@github.com:GEWA-codecrushers/DevOps.git"
REPO_DIR="${DEVOPS_REPO:-$HOME/repo/DevOps}"
SSH_KEY="$HOME/.ssh/id_ed25519"

# Read from the controlling terminal so prompts work under `curl ... | bash`
# (where stdin is the piped script, not the keyboard). Avoids bash-specific
# `read -p` so the same code runs under zsh too. Drains any buffered
# keystrokes first so a stray Enter from the previous step (e.g. while
# apt-get was running) doesn't get auto-consumed and skip past the prompt.
read_tty() {
  local var="$1" prompt="$2"
  if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    echo "error: no controlling terminal — re-run from an interactive shell" >&2
    exit 1
  fi
  if [ -n "${BASH_VERSION:-}" ]; then
    while read -r -t 0.05 -n 4096 _drain </dev/tty 2>/dev/null; do :; done
  fi
  printf '%s' "$prompt" >/dev/tty
  IFS= read -r "$var" </dev/tty
}

echo "[1/5] installing prerequisites (sudo)..."
sudo apt-get update
sudo apt-get install -y git openssh-client curl ca-certificates

echo "[2/5] ensuring an SSH key exists..."
if [ ! -f "$SSH_KEY" ]; then
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  read_tty SSH_EMAIL "Email for the new SSH key: "
  ssh-keygen -t ed25519 -C "$SSH_EMAIL" -f "$SSH_KEY" -N ""
  echo "created $SSH_KEY"
else
  echo "reusing existing $SSH_KEY"
fi

echo
echo "[3/5] register the key with GitHub"
echo "----- your public key -----"
cat "$SSH_KEY.pub"
echo "---------------------------"
echo "If it isn't there already, add it at: https://github.com/settings/ssh/new"
read_tty _CONTINUE "Press Enter once the key is added..."

mkdir -p "$HOME/.ssh"
if ! grep -q "^github.com " "$HOME/.ssh/known_hosts" 2>/dev/null; then
  ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null
fi

# ssh -T to GitHub always exits non-zero ("no shell access"), so check the
# success phrase in the output instead of the exit code.
ssh_output=$(ssh -T -o BatchMode=yes git@github.com 2>&1 || true)
if ! echo "$ssh_output" | grep -q "successfully authenticated"; then
  echo "SSH to GitHub failed:"
  echo "$ssh_output"
  echo
  echo "Confirm the key was added on GitHub, then re-run."
  exit 1
fi
echo "SSH auth OK."

echo "[4/5] cloning DevOps repo to $REPO_DIR..."
mkdir -p "$(dirname "$REPO_DIR")"
if [ -d "$REPO_DIR/.git" ]; then
  echo "already present; pulling latest..."
  git -C "$REPO_DIR" pull --ff-only
elif [ -e "$REPO_DIR" ]; then
  echo "error: $REPO_DIR exists but is not a git repo. Move it aside and re-run."
  exit 1
else
  git clone "$REPO_SSH" "$REPO_DIR"
fi

echo "[5/5] handing off to setup.sh..."
exec bash "$REPO_DIR/scripts/setup/ubuntu/setup.sh"

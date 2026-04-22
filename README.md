# devops-bootstrap

Public bootstrap for GEWA-codecrushers developer onboarding. Gets a fresh Ubuntu VM to the point where the (private) [DevOps repo](https://github.com/GEWA-codecrushers/DevOps) can be cloned and its `setup.sh` can run.

## Usage

On a fresh Ubuntu VM:

```bash
curl -fsSL https://raw.githubusercontent.com/GEWA-codecrushers/devops-bootstrap/main/bootstrap.sh | bash
```

What it does:

1. Installs prerequisites (`git`, `openssh-client`, `curl`)
2. Generates an ed25519 SSH key if you don't have one
3. Shows the public key and waits for you to add it at <https://github.com/settings/ssh/new>
4. Verifies `ssh -T git@github.com`
5. Clones the DevOps repo to `~/repo/DevOps`
6. Hands off to `scripts/setup/ubuntu/setup.sh` for the full dev-env install

## Why this repo exists

The DevOps repo is private, so a fresh VM can't `curl` `setup.sh` directly from it — cloning it requires an SSH key and GitHub auth that don't exist yet. This tiny public repo exists solely to carry the bootstrap over that first hop. See [DevOps#60](https://github.com/GEWA-codecrushers/DevOps/issues/60) for the design discussion.

## Editing

**Do not edit `bootstrap.sh` here directly.** The canonical copy lives in the DevOps repo at [`scripts/setup/ubuntu/bootstrap.sh`](https://github.com/GEWA-codecrushers/DevOps/blob/main/scripts/setup/ubuntu/bootstrap.sh). After merging a change there, sync it here:

```bash
# From your DevOps checkout, with this repo cloned alongside:
cp scripts/setup/ubuntu/bootstrap.sh ../devops-bootstrap/bootstrap.sh
cd ../devops-bootstrap
git add bootstrap.sh
git commit -m "sync bootstrap.sh from DevOps@$(git -C ../DevOps rev-parse --short main)"
git push
```

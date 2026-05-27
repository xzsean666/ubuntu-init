# ubuntu-bootstrap

Ubuntu 24.04 / 26.04 personal developer environment bootstrap scripts.

The MVP target is a fresh Ubuntu machine that can become usable for development with one command:

```bash
./bootstrap.sh --desktop
```

or for a server baseline:

```bash
./bootstrap.sh --server --ssh-key "ssh-ed25519 AAAA..."
```

## What Desktop Mode Installs

`--desktop` runs these modules in order:

```text
base ssh docker node pnpm python uv gh codex claude antigravity fcitx5 chrome vscode
```

That includes:

- Common system and build tools
- OpenSSH server and optional public key setup
- Docker Engine, Compose plugin, Buildx plugin
- Docker registry mirrors and BuildKit mirror config when a China public IP is detected
- nvm, latest Node.js LTS, npm, pnpm
- Python 3, pip, venv, pipx, uv
- GitHub CLI
- Codex CLI, Claude Code CLI, Antigravity CLI
- Fcitx5 Chinese input
- Google Chrome
- VS Code

## What Server Mode Installs

`--server` runs:

```text
base ssh docker gh
```

BaoTa is intentionally not part of the default server plan because it runs an external root installer and changes server state substantially. Install it only when you explicitly request it:

```bash
./bootstrap.sh --server --baota
```

For a pinned BaoTa installer, set `BAOTA_INSTALL_SHA256`. Without it, the script warns before running the remote installer because `--baota` was explicitly requested.

## Dry Run

Dry run is the safest way to test a new machine or this repository:

```bash
./bootstrap.sh --desktop --dry-run
UBUNTU_BOOTSTRAP_COUNTRY=CN ./bootstrap.sh --desktop --dry-run
./bootstrap.sh --only docker,node,pnpm --dry-run
```

Dry run logs the commands but does not install packages, write system config, or call network detection.
For install checks, dry run behaves like a fresh machine so the planned commands are visible even if your current machine already has the tool installed.
Dry run does not prove that remote apt repositories, GitHub releases, npm packages, or vendor download URLs are currently reachable.

## Already Installed Software

Normal runs skip software that is already installed. Apt packages are filtered before `apt-get install`, so only missing packages are installed. Tool modules such as Docker, Node.js, pnpm, uv, GitHub CLI, AI CLIs, Chrome, VS Code, BaoTa, and optional desktop apps return `[SKIPPED]` when the command or installation marker already exists.

Modules that also manage configuration, such as SSH hardening, authorized SSH keys, Docker group membership, and China mirror configuration, still apply the requested configuration even when the main package is already present.

## Testing This Repo

```bash
./tests/dry-run.sh
```

The test script runs `bash -n` over all shell files and exercises desktop, server, and custom module dry runs.
It also uses `--strict` for positive cases and checks invalid-module, invalid-skip, invalid SSH key, root-target, and conflicting-mirror negative cases.

## Module Flags

You can run modules directly:

```bash
./bootstrap.sh --docker
./bootstrap.sh --chrome --vscode
./bootstrap.sh --only docker,node,pnpm,uv
```

Available module ids:

```text
base ssh docker node pnpm python uv gh codex claude antigravity
fcitx5 chrome vscode baota slack wechat clash youdao navicat
```

Optional desktop extras are best-effort:

```bash
./bootstrap.sh --slack --wechat --clash
```

Direct third-party `.deb` installers are gated by SHA256 by default:

```bash
WECHAT_DEB_SHA256="..." ./bootstrap.sh --wechat
CLASH_VERGE_DEB_URL="https://..." CLASH_VERGE_DEB_SHA256="..." ./bootstrap.sh --clash
YOUDAO_DEB_URL="https://..." YOUDAO_DEB_SHA256="..." ./bootstrap.sh --youdao
NAVICAT_DEB_URL="https://..." NAVICAT_DEB_SHA256="..." ./bootstrap.sh --navicat
```

Set `ALLOW_UNVERIFIED_DEB=1` only when you intentionally accept installing a downloaded package without hash verification. For Clash Verge, automatic latest-release resolution is disabled unless `CLASH_VERGE_ALLOW_LATEST=1` is set.

When Clash Verge is installed, the script also configures system proxy environment variables for the default mixed port `7897`:

```text
/etc/environment:
http_proxy="http://127.0.0.1:7897"
https_proxy="http://127.0.0.1:7897"
all_proxy="socks5://127.0.0.1:7897"
no_proxy="localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

/etc/sudoers.d/90-ubuntu-bootstrap-proxy-env:
Defaults env_keep += "http_proxy https_proxy all_proxy no_proxy"
```

Override or disable that behavior:

```bash
CLASH_VERGE_PROXY_PORT=7890 ./bootstrap.sh --clash
CLASH_VERGE_CONFIGURE_PROXY_ENV=0 ./bootstrap.sh --clash
```

## China Network Behavior

The script detects the current public IP country unless disabled. If the detected country is `CN`, it configures:

- Ubuntu apt mirror rewrite for default Ubuntu archive URLs
- Docker daemon `registry-mirrors`
- BuildKit `/etc/docker/buildkitd.toml`
- A buildx builder named `ubuntu-bootstrap`
- Node.js downloads through `NVM_NODEJS_ORG_MIRROR`
- npm registry mirror when npm is installed
- pip and uv index defaults

Force or disable mirror behavior:

```bash
./bootstrap.sh --desktop --force-china-mirrors
./bootstrap.sh --desktop --no-china-mirrors
./bootstrap.sh --desktop --skip-network-check
```

Override or disable the Ubuntu apt mirror:

```bash
UBUNTU_APT_MIRROR=https://mirrors.tuna.tsinghua.edu.cn/ubuntu ./bootstrap.sh --desktop
NO_APT_MIRROR=1 ./bootstrap.sh --desktop
```

Docker mirror endpoints:

```json
{
  "registry-mirrors": [
    "https://docker.1ms.run",
    "https://docker.m.daocloud.io",
    "https://docker.xuanyuan.me"
  ]
}
```

BuildKit uses host-form mirror entries for `docker.io` in `/etc/docker/buildkitd.toml`, so `docker build`, `docker buildx build`, and `docker compose build` can use the same mirror environment as `docker pull`.

To force the custom builder explicitly:

```bash
docker buildx build --builder ubuntu-bootstrap --load -t myimage:dev .
docker compose build --builder ubuntu-bootstrap
BUILDX_BUILDER=ubuntu-bootstrap docker build .
```

## Failure Strategy

Each module runs as an independent step. Third-party download or npm failures are recorded in the final summary and the bootstrap continues through the remaining planned modules. If any module fails, the final process exit code is non-zero after the summary is printed.

Use `--strict` in automation to also fail on any recorded failure if a future module accidentally swallows its return code:

```bash
./bootstrap.sh --desktop --strict
```

## Logs

When run as root, logs default to:

```text
/var/log/ubuntu-bootstrap.log
```

When run as a normal user, logs default to:

```text
./logs/ubuntu-bootstrap.log
```

Override with:

```bash
./bootstrap.sh --desktop --log-file /tmp/bootstrap.log
```

## Notes

- The target user is `UBUNTU_BOOTSTRAP_USER`, or `SUDO_USER`, or the current user.
- Per-user tooling modules such as Node.js, Python user PATH setup, uv, AI CLIs, and Fcitx5 refuse a root target unless `ALLOW_ROOT_USER_TOOLS=1` is set. Prefer running with `sudo` from your normal user or setting `UBUNTU_BOOTSTRAP_USER=<user>`.
- `--harden-ssh` writes `/etc/ssh/sshd_config.d/99-ubuntu-bootstrap.conf`, disables SSH password login, validates `sshd -t`, and reloads/restarts SSH.
- Docker group membership usually requires logging out and back in before the current shell can run `docker` without `sudo`.
- Existing Docker daemon JSON is merged and backed up instead of overwritten.
- Existing BuildKit config is backed up and merged where practical. A single-line existing `mirrors = [...]` under `[registry."docker.io"]` is merged; ambiguous multi-line mirror entries are refused instead of edited blindly.
- In China network mode, the script recreates the script-managed `ubuntu-bootstrap` buildx builder so it uses `/etc/docker/buildkitd.toml`.
- Proprietary or unstable desktop software download URLs are kept best-effort rather than silently using unofficial mirrors.
- GitHub CLI keyring uses a pinned SHA256 by default; override with `GH_KEYRING_SHA256` or set it empty to disable that check.
- Some official installer paths still trust HTTPS plus the vendor's own installer or apt signing key, including Claude native installer, Antigravity installer, Chrome signing key, and VS Code signing key.

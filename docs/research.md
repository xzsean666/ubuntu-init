# Research Notes

Checked on 2026-05-26.

## Core Install Sources

- Docker Engine for Ubuntu: https://docs.docker.com/engine/install/ubuntu/
  - Official docs list Ubuntu 26.04 and 24.04 support.
  - Recommended install path is the Docker apt repository.
  - Packages needed for MVP: `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`.
- Docker BuildKit configuration: https://docs.docker.com/build/buildkit/configure/
  - Buildx can create a `docker-container` builder with `--buildkitd-config`.
  - Registry mirrors belong in BuildKit config under `[registry."docker.io"]`.
- Docker registry mirror daemon config: https://docs.docker.com/docker-hub/image-library/mirror/
  - Docker daemon supports `registry-mirrors` in `/etc/docker/daemon.json`.
- nvm: https://github.com/nvm-sh/nvm
  - Official install method is the versioned install script from `raw.githubusercontent.com/nvm-sh/nvm/<version>/install.sh`.
  - The script resolves the latest release through GitHub API, with a fallback version.
- pnpm: https://pnpm.io/installation
  - pnpm 11 requires Node.js 22+ unless using standalone `@pnpm/exe`.
  - Recommended Corepack flow updates Corepack first, then enables/prepares pnpm.
- uv: https://docs.astral.sh/uv/getting-started/installation/
  - Official Linux install command is `curl -LsSf https://astral.sh/uv/install.sh | sh`.
  - The project downloads the installer to a temporary file before executing it, so download failures are detected before the script runs.
- GitHub CLI: https://github.com/cli/cli/blob/trunk/docs/install_linux.md
  - Official Debian/Ubuntu install path uses `https://cli.github.com/packages`.
  - The script pins the downloaded GitHub CLI keyring SHA256 by default and allows `GH_KEYRING_SHA256` override.
- Codex CLI: https://github.com/openai/codex and https://help.openai.com/en/articles/11096431
  - Official npm install is `npm install -g @openai/codex`.
- Claude Code CLI: https://code.claude.com/docs/en/getting-started
  - Current official preferred install is `curl -fsSL https://claude.ai/install.sh | bash`.
  - The npm package `@anthropic-ai/claude-code` remains available as a fallback when `CLAUDE_INSTALL_METHOD=npm` is set or the native installer fails after Node is installed.
  - Current implementation executes the official native installer after downloading it to a temporary file, but does not add a separate manifest or package-signature verification layer.
- Antigravity CLI: https://www.antigravity.google/product/antigravity-cli and https://www.antigravity.google/download
  - Official Linux install command is `curl -fsSL https://antigravity.google/cli/install.sh | bash`.

## Desktop Install Sources

- Google Chrome: https://www.google.com/linuxrepositories/ and https://www.google.com/chrome/
  - The script uses Google's Linux apt repository and signing key so Chrome can update through apt.
  - Chrome is automated only for `amd64`.
  - The current implementation trusts HTTPS retrieval of Google's Linux signing key, then relies on apt package signatures.
- VS Code: https://code.visualstudio.com/docs/setup/linux
  - Microsoft apt repository is the most maintainable install path for Ubuntu.
  - The current implementation trusts HTTPS retrieval of Microsoft's signing key, then relies on apt package signatures.
- Fcitx5:
  - Ubuntu packages: `fcitx5`, `fcitx5-chinese-addons`, GTK/Qt frontends, `im-config`.
  - The script configures the user input method with `im-config -n fcitx5` and adds standard environment variables.

## Design Decisions

- Default desktop mode follows the MVP list from the project brief.
- Default server mode is limited to the open baseline: base, SSH, Docker, and GitHub CLI. BaoTa is explicit via `--baota` because it runs a remote root installer.
- Third-party CLIs are separate steps, so a timeout or npm failure does not stop Docker, Node, Python, or GUI setup.
- Dry-run is implemented in the command runner, with module-specific dry-run branches only where needed for downloads, key installation, and latest-release lookup. It validates local control flow but does not validate remote asset availability.
- Existing root config files are backed up and merged/appended where practical.
- Docker daemon JSON is merged through Python JSON parsing. BuildKit TOML is merged conservatively: single-line existing `mirrors = [...]` entries under `[registry."docker.io"]` are merged, missing mirror entries are inserted, and ambiguous multi-line mirror entries fail rather than being edited blindly.
- The script-managed `ubuntu-bootstrap` buildx builder is recreated in China network mode so reruns pick up the current `/etc/docker/buildkitd.toml`.
- apt mirror rewriting is conservative: only default Ubuntu archive/security URLs are replaced, and custom source files are left alone.
- BaoTa, WeChat, Clash Verge, Youdao, and Navicat are treated as best-effort because their unattended Linux install surfaces are more volatile or proprietary than the MVP tools.
- Direct `.deb` installers for WeChat, Clash Verge, Youdao, and Navicat require SHA256 verification unless `ALLOW_UNVERIFIED_DEB=1` is set. Clash latest-release resolution is opt-in with `CLASH_VERGE_ALLOW_LATEST=1`.
- SSH hardening is opt-in with `--harden-ssh`; key-based login remains enabled, password login is disabled, and `sshd -t` must pass before reload/restart.

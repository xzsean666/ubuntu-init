#!/usr/bin/env bash
# shellcheck disable=SC2016

resolve_nvm_version() {
  if [[ -n "${NVM_VERSION:-}" ]]; then
    echo "$NVM_VERSION"
    return 0
  fi
  if is_dry_run || ! command_exists curl; then
    echo "v0.40.4"
    return 0
  fi
  local latest
  latest="$(timeout 10 curl -fsSL --connect-timeout 5 --max-time 8 https://api.github.com/repos/nvm-sh/nvm/releases/latest 2>/dev/null | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1 || true)"
  echo "${latest:-v0.40.4}"
}

nvm_shell() {
  local seconds="$1"
  shift
  local script
  script='export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"; '"$*"
  run_user_shell "$seconds" "$script"
}

install_node() {
  require_non_root_target "Node.js" || return $?
  if ! is_dry_run && nvm_shell 60 'command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1'; then
    nvm_shell 120 'node --version && npm --version' || true
    skip_step "Node.js and npm are already installed for $TARGET_USER."
    return $?
  fi

  apt_install ca-certificates curl git build-essential python3 || return $?

  local nvm_version install_url
  nvm_version="$(resolve_nvm_version)"
  install_url="${NVM_INSTALL_URL:-https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_version}/install.sh}"

  if ! is_dry_run && nvm_shell 60 'command -v nvm >/dev/null 2>&1'; then
    log_info "nvm is already installed for $TARGET_USER."
  else
    run_downloaded_user_script "$install_url" bash "export PROFILE=/dev/null; " || return $?
  fi

  append_user_file_if_missing "$TARGET_HOME/.bashrc" "ubuntu-bootstrap nvm" '# ubuntu-bootstrap nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"'

  local node_mirror_prefix=""
  if is_china_network; then
    node_mirror_prefix='export NVM_NODEJS_ORG_MIRROR="https://npmmirror.com/mirrors/node"; '
  fi

  nvm_shell 1200 "${node_mirror_prefix}nvm install --lts && nvm alias default \"lts/*\" && nvm use default && node --version && npm --version" || return $?

  if is_china_network; then
    nvm_shell 120 'current="$(npm config get registry 2>/dev/null || true)"; if [ -z "$current" ] || [ "$current" = "https://registry.npmjs.org/" ]; then npm config set registry https://registry.npmmirror.com; else echo "npm registry already customized: $current"; fi'
  fi
}

install_pnpm() {
  require_non_root_target "pnpm" || return $?
  if ! nvm_shell 60 'command -v npm >/dev/null 2>&1'; then
    fail_step "npm is not available; run the node module first."
    return $?
  fi

  if ! is_dry_run && nvm_shell 60 'command -v pnpm >/dev/null 2>&1'; then
    nvm_shell 120 'pnpm --version' || true
    skip_step "pnpm is already installed for $TARGET_USER."
    return $?
  fi

  nvm_shell 900 'npm --fetch-retries=2 --fetch-timeout=300000 install -g pnpm@latest || (npm --fetch-retries=2 --fetch-timeout=300000 install --global corepack@latest && corepack enable pnpm && corepack prepare pnpm@latest --activate)' || return $?

  if is_china_network; then
    nvm_shell 120 'pnpm config get registry | grep -qx "https://registry.npmjs.org/" && pnpm config set registry https://registry.npmmirror.com || true'
  fi

  nvm_shell 120 'pnpm --version'
}

#!/usr/bin/env bash
# shellcheck disable=SC2016

npm_global_install() {
  local package="$1"
  local command_name="$2"
  require_non_root_target "$command_name" || return $?
  if ! nvm_shell 60 'command -v npm >/dev/null 2>&1'; then
    fail_step "npm is not available; run the node module first."
    return $?
  fi
  if ! is_dry_run && nvm_shell 60 "command -v '$command_name' >/dev/null 2>&1"; then
    log_info "$command_name is already installed."
  else
    nvm_shell "$DOWNLOAD_TIMEOUT" "npm --fetch-retries=2 --fetch-timeout=300000 install -g '$package@latest'" || return $?
  fi
  nvm_shell 120 "command -v '$command_name' && ('$command_name' --version || '$command_name' -v || true)"
}

install_codex_cli() {
  npm_global_install "@openai/codex" "codex"
}

install_claude_cli() {
  require_non_root_target "Claude Code CLI" || return $?
  apt_install ca-certificates curl || return $?

  if ! is_dry_run && run_user_shell 60 'export PATH="$HOME/.local/bin:$PATH"; command -v claude >/dev/null 2>&1'; then
    run_user_shell 120 'export PATH="$HOME/.local/bin:$PATH"; claude --version || claude -v || true'
    return 0
  fi

  append_user_file_if_missing "$TARGET_HOME/.bashrc" "ubuntu-bootstrap local bin" '# ubuntu-bootstrap local bin
export PATH="$HOME/.local/bin:$PATH"'

  case "${CLAUDE_INSTALL_METHOD:-native}" in
    native)
      if run_downloaded_user_script https://claude.ai/install.sh bash && run_user_shell 120 'export PATH="$HOME/.local/bin:$PATH"; command -v claude && (claude --version || claude -v || true)'; then
        return 0
      fi
      log_warn "Claude native installer failed; trying npm package fallback."
      npm_global_install "@anthropic-ai/claude-code" "claude"
      ;;
    npm)
      npm_global_install "@anthropic-ai/claude-code" "claude"
      ;;
    *)
      fail_step "Unsupported CLAUDE_INSTALL_METHOD=${CLAUDE_INSTALL_METHOD:-}"
      return $?
      ;;
  esac
}

install_antigravity_cli() {
  require_non_root_target "Antigravity CLI" || return $?
  apt_install ca-certificates curl || return $?

  append_user_file_if_missing "$TARGET_HOME/.bashrc" "ubuntu-bootstrap local bin" '# ubuntu-bootstrap local bin
export PATH="$HOME/.local/bin:$PATH"'

  if ! is_dry_run && run_user_shell 60 'export PATH="$HOME/.local/bin:$PATH"; command -v agy >/dev/null 2>&1'; then
    log_info "agy is already installed."
  else
    run_downloaded_user_script https://antigravity.google/cli/install.sh bash || return $?
  fi
  run_user_shell 120 'export PATH="$HOME/.local/bin:$PATH"; command -v agy && (agy --version || true)'
}

#!/usr/bin/env bash
# shellcheck disable=SC2016

pnpm_global_install() {
  local package="$1"
  local command_name="$2"
  require_non_root_target "$command_name" || return $?
  if ! nvm_shell 60 'command -v pnpm >/dev/null 2>&1'; then
    fail_step "pnpm is not available; run the pnpm module first."
    return $?
  fi
  if ! is_dry_run && nvm_shell 60 "command -v '$command_name' >/dev/null 2>&1"; then
    nvm_shell 120 "('$command_name' --version || '$command_name' -v || true)"
    skip_step "$command_name is already installed."
    return $?
  else
    nvm_shell "$DOWNLOAD_TIMEOUT" "pnpm add -g '$package@latest'" || return $?
  fi
  nvm_shell 120 "command -v '$command_name' && ('$command_name' --version || '$command_name' -v || true)"
}

install_codex_cli() {
  pnpm_global_install "@openai/codex" "codex"
}

install_claude_cli() {
  require_non_root_target "Claude Code CLI" || return $?

  if ! is_dry_run && run_user_shell 60 'export PATH="$HOME/.local/bin:$PATH"; command -v claude >/dev/null 2>&1'; then
    run_user_shell 120 'export PATH="$HOME/.local/bin:$PATH"; claude --version || claude -v || true' || true
    skip_step "Claude Code CLI is already installed for $TARGET_USER."
    return $?
  fi

  apt_install ca-certificates curl || return $?

  append_user_file_if_missing "$TARGET_HOME/.bashrc" "ubuntu-bootstrap local bin" '# ubuntu-bootstrap local bin
export PATH="$HOME/.local/bin:$PATH"'

  case "${CLAUDE_INSTALL_METHOD:-native}" in
    native)
      if run_downloaded_user_script https://claude.ai/install.sh bash && run_user_shell 120 'export PATH="$HOME/.local/bin:$PATH"; command -v claude && (claude --version || claude -v || true)'; then
        return 0
      fi
      log_warn "Claude native installer failed; trying npm package fallback."
      pnpm_global_install "@anthropic-ai/claude-code" "claude"
      ;;
    npm)
      pnpm_global_install "@anthropic-ai/claude-code" "claude"
      ;;
    *)
      fail_step "Unsupported CLAUDE_INSTALL_METHOD=${CLAUDE_INSTALL_METHOD:-}"
      return $?
      ;;
  esac
}

install_antigravity_cli() {
  require_non_root_target "Antigravity CLI" || return $?

  if ! is_dry_run && run_user_shell 60 'export PATH="$HOME/.local/bin:$PATH"; command -v agy >/dev/null 2>&1'; then
    run_user_shell 120 'export PATH="$HOME/.local/bin:$PATH"; agy --version || true' || true
    skip_step "Antigravity CLI is already installed for $TARGET_USER."
    return $?
  fi

  apt_install ca-certificates curl || return $?

  append_user_file_if_missing "$TARGET_HOME/.bashrc" "ubuntu-bootstrap local bin" '# ubuntu-bootstrap local bin
export PATH="$HOME/.local/bin:$PATH"'

  run_downloaded_user_script https://antigravity.google/cli/install.sh bash || return $?
  run_user_shell 120 'export PATH="$HOME/.local/bin:$PATH"; command -v agy && (agy --version || true)'
}

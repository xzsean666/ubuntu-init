#!/usr/bin/env bash
# shellcheck disable=SC2016

install_python() {
  require_non_root_target "Python user tooling" || return $?
  apt_install python3 python3-dev python3-pip python3-venv pipx || return $?

  append_user_file_if_missing "$TARGET_HOME/.bashrc" "ubuntu-bootstrap local bin" '# ubuntu-bootstrap local bin
export PATH="$HOME/.local/bin:$PATH"'

  if is_china_network; then
    run_user_shell 120 'python3 -m pip config get global.index-url >/dev/null 2>&1 || python3 -m pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple' || log_warn "Could not configure pip mirror; continuing."
  fi

  run_cmd 120 python3 --version
}

install_uv() {
  require_non_root_target "uv" || return $?
  if ! is_dry_run && run_user_shell 60 'export PATH="$HOME/.local/bin:$PATH"; command -v uv >/dev/null 2>&1 || [ -x "$HOME/.local/bin/uv" ]'; then
    run_user_shell 120 'export PATH="$HOME/.local/bin:$PATH"; uv --version' || true
    skip_step "uv is already installed for $TARGET_USER."
    return $?
  fi

  apt_install ca-certificates curl || return $?

  append_user_file_if_missing "$TARGET_HOME/.bashrc" "ubuntu-bootstrap local bin" '# ubuntu-bootstrap local bin
export PATH="$HOME/.local/bin:$PATH"'

  run_downloaded_user_script https://astral.sh/uv/install.sh sh 'env UV_INSTALL_DIR="$HOME/.local/bin" ' || return $?

  if is_china_network; then
    append_user_file_if_missing "$TARGET_HOME/.bashrc" "ubuntu-bootstrap uv mirror" '# ubuntu-bootstrap uv mirror
export UV_DEFAULT_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple"'
  fi

  run_user_shell 120 'export PATH="$HOME/.local/bin:$PATH"; uv --version'
}

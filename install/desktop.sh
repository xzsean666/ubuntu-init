#!/usr/bin/env bash
# shellcheck disable=SC2034

install_fcitx5() {
  require_non_root_target "Fcitx5 Chinese input" || return $?
  if ! is_dry_run && command_exists fcitx5; then
    skip_step "Fcitx5 is already installed."
    return $?
  fi

  apt_install \
    fcitx5 \
    fcitx5-chinese-addons \
    fcitx5-config-qt \
    fcitx5-frontend-gtk2 \
    fcitx5-frontend-gtk3 \
    fcitx5-frontend-gtk4 \
    fcitx5-frontend-qt5 \
    fcitx5-frontend-qt6 \
    fonts-noto-cjk \
    im-config || return $?

  run_user_shell 120 'im-config -n fcitx5 || true'

  append_user_file_if_missing "$TARGET_HOME/.profile" "ubuntu-bootstrap fcitx5" '# ubuntu-bootstrap fcitx5
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx'
}

install_chrome() {
  local arch
  arch="$(dpkg --print-architecture)"
  if [[ "$arch" != "amd64" ]]; then
    skip_step "Google Chrome Linux stable is only available for amd64 from Google's Linux repository."
    return $?
  fi

  if ! is_dry_run && { command_exists google-chrome || command_exists google-chrome-stable; }; then
    run_cmd 120 google-chrome --version || run_cmd 120 google-chrome-stable --version || true
    skip_step "Google Chrome is already installed."
    return $?
  fi

  apt_install ca-certificates curl gnupg || return $?
  run_sudo 60 install -m 0755 -d /etc/apt/keyrings || return $?

  if is_dry_run; then
    log_info "Would install Google Linux apt key and Chrome repository."
  else
    local tmp_key tmp_gpg
    tmp_key="$(mktemp)"
    tmp_gpg="$(mktemp)"
    download_to https://dl.google.com/linux/linux_signing_key.pub "$tmp_key" || {
      rm -f "$tmp_key" "$tmp_gpg"
      return 1
    }
    gpg --dearmor <"$tmp_key" >"$tmp_gpg" || {
      rm -f "$tmp_key" "$tmp_gpg"
      return 1
    }
    run_sudo 60 install -m 0644 "$tmp_gpg" /etc/apt/keyrings/google-linux.gpg || {
      rm -f "$tmp_key" "$tmp_gpg"
      return 1
    }
    rm -f "$tmp_key" "$tmp_gpg"
  fi

  write_root_file 0644 /etc/apt/sources.list.d/google-chrome.list \
    "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-linux.gpg] https://dl.google.com/linux/chrome/deb/ stable main
"

  APT_UPDATED=0
  apt_update || return $?
  apt_install google-chrome-stable || return $?
}

install_vscode() {
  local arch
  arch="$(dpkg --print-architecture)"
  case "$arch" in
    amd64|arm64|armhf) ;;
    *)
      skip_step "VS Code apt repository is not configured for architecture: $arch"
      return $?
      ;;
  esac

  if ! is_dry_run && command_exists code; then
    run_cmd 120 code --version || true
    skip_step "VS Code is already installed."
    return $?
  fi

  apt_install ca-certificates curl gnupg || return $?
  run_sudo 60 install -m 0755 -d /etc/apt/keyrings || return $?

  if is_dry_run; then
    log_info "Would install Microsoft apt key and VS Code repository."
  else
    local tmp_key tmp_gpg
    tmp_key="$(mktemp)"
    tmp_gpg="$(mktemp)"
    download_to https://packages.microsoft.com/keys/microsoft.asc "$tmp_key" || {
      rm -f "$tmp_key" "$tmp_gpg"
      return 1
    }
    gpg --dearmor <"$tmp_key" >"$tmp_gpg" || {
      rm -f "$tmp_key" "$tmp_gpg"
      return 1
    }
    run_sudo 60 install -m 0644 "$tmp_gpg" /etc/apt/keyrings/packages.microsoft.gpg || {
      rm -f "$tmp_key" "$tmp_gpg"
      return 1
    }
    rm -f "$tmp_key" "$tmp_gpg"
  fi

  write_root_file 0644 /etc/apt/sources.list.d/vscode.list \
    "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main
"

  APT_UPDATED=0
  apt_update || return $?
  apt_install code || return $?
}

#!/usr/bin/env bash

install_slack() {
  if ! is_dry_run && command_exists slack; then
    run_cmd 120 slack --version || true
    return 0
  fi
  if ! has_systemd; then
    skip_step "Slack snap install requires systemd/snapd."
    return $?
  fi
  apt_install snapd || return $?
  run_sudo 300 systemctl enable --now snapd.socket || return $?
  run_sudo 1200 snap install slack
}

install_wechat() {
  local arch url
  arch="$(dpkg --print-architecture)"
  if [[ "$arch" != "amd64" ]]; then
    skip_step "WeChat Linux direct .deb URL is only configured for amd64."
    return $?
  fi

  if ! is_dry_run && { command_exists wechat || command_exists weixin; }; then
    log_info "WeChat appears to be installed."
    return 0
  fi

  url="${WECHAT_DEB_URL:-https://dldir1.qq.com/weixin/Universal/Linux/WeChatLinux_x86_64.deb}"
  if [[ -z "${WECHAT_DEB_SHA256:-}" && "${ALLOW_UNVERIFIED_DEB:-0}" != "1" ]]; then
    skip_step "Set WECHAT_DEB_SHA256 to install WeChat, or ALLOW_UNVERIFIED_DEB=1 to install without hash verification."
    return $?
  fi
  apt_install ca-certificates curl || return $?
  install_deb_from_url wechat "$url" "${WECHAT_DEB_SHA256:-}"
}

install_clash_verge() {
  if ! is_dry_run && { command_exists clash-verge || command_exists clash-verge-service; }; then
    log_info "Clash Verge appears to be installed."
    return 0
  fi

  local arch pattern url
  arch="$(dpkg --print-architecture)"
  case "$arch" in
    amd64) pattern='amd64.*\.deb$|x86_64.*\.deb$' ;;
    arm64) pattern='arm64.*\.deb$|aarch64.*\.deb$' ;;
    *)
      skip_step "Unsupported architecture for automatic Clash Verge install: $arch"
      return $?
      ;;
  esac

  if [[ -n "${CLASH_VERGE_DEB_URL:-}" ]]; then
    if [[ -z "${CLASH_VERGE_DEB_SHA256:-}" && "${ALLOW_UNVERIFIED_DEB:-0}" != "1" ]]; then
      skip_step "Set CLASH_VERGE_DEB_SHA256 to install Clash Verge, or ALLOW_UNVERIFIED_DEB=1 to install without hash verification."
      return $?
    fi
    apt_install ca-certificates curl || return $?
    install_deb_from_url clash-verge "$CLASH_VERGE_DEB_URL" "${CLASH_VERGE_DEB_SHA256:-}"
    return $?
  fi

  if [[ "${CLASH_VERGE_ALLOW_LATEST:-0}" != "1" ]]; then
    skip_step "Set CLASH_VERGE_DEB_URL and CLASH_VERGE_DEB_SHA256, or CLASH_VERGE_ALLOW_LATEST=1 to resolve the latest GitHub release."
    return $?
  fi
  if [[ -z "${CLASH_VERGE_DEB_SHA256:-}" && "${ALLOW_UNVERIFIED_DEB:-0}" != "1" ]]; then
    skip_step "Latest Clash Verge release install is unverified; set ALLOW_UNVERIFIED_DEB=1 to allow it."
    return $?
  fi

  if is_dry_run; then
    log_info "Would resolve latest Clash Verge Rev .deb from GitHub because CLASH_VERGE_ALLOW_LATEST=1."
    return 0
  fi

  apt_install ca-certificates curl python3 || return $?
  url="$(github_latest_asset_url clash-verge-rev/clash-verge-rev "$pattern")" || return $?
  install_deb_from_url clash-verge "$url" "${CLASH_VERGE_DEB_SHA256:-}"
}

install_youdao_note() {
  if [[ -z "${YOUDAO_DEB_URL:-}" ]]; then
    skip_step "No stable official unattended Linux download URL is configured; set YOUDAO_DEB_URL to install."
    return $?
  fi
  if [[ -z "${YOUDAO_DEB_SHA256:-}" && "${ALLOW_UNVERIFIED_DEB:-0}" != "1" ]]; then
    skip_step "Set YOUDAO_DEB_SHA256 to install Youdao Note, or ALLOW_UNVERIFIED_DEB=1 to install without hash verification."
    return $?
  fi
  apt_install ca-certificates curl || return $?
  install_deb_from_url youdao-note "$YOUDAO_DEB_URL" "${YOUDAO_DEB_SHA256:-}"
}

install_navicat() {
  if [[ -z "${NAVICAT_DEB_URL:-}" ]]; then
    skip_step "Navicat is proprietary and versioned; set NAVICAT_DEB_URL to install your licensed package."
    return $?
  fi
  if [[ -z "${NAVICAT_DEB_SHA256:-}" && "${ALLOW_UNVERIFIED_DEB:-0}" != "1" ]]; then
    skip_step "Set NAVICAT_DEB_SHA256 to install Navicat, or ALLOW_UNVERIFIED_DEB=1 to install without hash verification."
    return $?
  fi
  apt_install ca-certificates curl || return $?
  install_deb_from_url navicat-premium "$NAVICAT_DEB_URL" "${NAVICAT_DEB_SHA256:-}"
}

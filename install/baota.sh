#!/usr/bin/env bash

install_baota() {
  if [[ -d /www/server/panel ]]; then
    log_info "BaoTa panel appears to be installed at /www/server/panel."
    return 0
  fi

  apt_install ca-certificates curl wget || return $?

  local url="${BAOTA_INSTALL_URL:-https://download.bt.cn/install/install_lts.sh}"
  if is_dry_run; then
    log_info "Would download and run BaoTa installer from $url"
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  download_to "$url" "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  if [[ -n "${BAOTA_INSTALL_SHA256:-}" ]]; then
    printf "%s  %s\n" "$BAOTA_INSTALL_SHA256" "$tmp" | sha256sum -c - || {
      rm -f "$tmp"
      return 1
    }
  else
    log_warn "BaoTa installer SHA256 is not set; running unverified remote installer because --baota was explicitly requested."
  fi
  chmod +x "$tmp"
  run_sudo_shell 3600 "yes y | bash '$tmp'"
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

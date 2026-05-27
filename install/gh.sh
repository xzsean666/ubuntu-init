#!/usr/bin/env bash
# shellcheck disable=SC2034

install_gh() {
  local keyring_sha256="${GH_KEYRING_SHA256-6084d5d7bd8e288441e0e94fc6275570895da18e6751f70f057485dc2d1a811b}"

  if ! is_dry_run && command_exists gh; then
    run_cmd 120 gh --version || true
    skip_step "GitHub CLI is already installed."
    return $?
  fi

  apt_install ca-certificates curl gnupg || return $?
  run_sudo 60 install -m 0755 -d /etc/apt/keyrings || return $?

  if is_dry_run; then
    log_info "Would install GitHub CLI apt key and repository."
  else
    local tmp_key
    tmp_key="$(mktemp)"
    download_to https://cli.github.com/packages/githubcli-archive-keyring.gpg "$tmp_key" || {
      rm -f "$tmp_key"
      return 1
    }
    if [[ -n "$keyring_sha256" ]]; then
      printf "%s  %s\n" "$keyring_sha256" "$tmp_key" | sha256sum -c - || {
        rm -f "$tmp_key"
        return 1
      }
    fi
    run_sudo 60 install -m 0644 "$tmp_key" /etc/apt/keyrings/githubcli-archive-keyring.gpg || {
      rm -f "$tmp_key"
      return 1
    }
    rm -f "$tmp_key"
  fi

  local arch
  arch="$(dpkg --print-architecture)"
  write_root_file 0644 /etc/apt/sources.list.d/github-cli.list \
    "deb [arch=$arch signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main
"

  APT_UPDATED=0
  apt_update || return $?
  apt_install gh || return $?
  run_cmd 120 gh --version
}

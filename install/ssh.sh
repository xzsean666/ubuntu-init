#!/usr/bin/env bash

install_ssh() {
  apt_install openssh-server openssh-client || return $?

  if has_systemd; then
    run_sudo 300 systemctl enable --now ssh || return $?
  else
    log_warn "systemd is not active; installed openssh-server but did not start ssh service."
  fi

  if [[ "${HARDEN_SSH:-0}" == "1" ]]; then
    configure_ssh_hardening || return $?
  fi

  if [[ -z "${SSH_PUBLIC_KEY:-}" ]]; then
    log_info "No --ssh-key provided; authorized_keys was not changed."
    return 0
  fi

  configure_authorized_key "$SSH_PUBLIC_KEY"
}

configure_authorized_key() {
  local key="$1"
  local ssh_dir="$TARGET_HOME/.ssh"
  local auth_file="$ssh_dir/authorized_keys"
  local q_ssh_dir q_auth_file tmp_key

  if [[ "$key" == *$'\n'* || "$key" == *$'\r'* ]]; then
    fail_step "SSH public key must be exactly one line."
    return $?
  fi

  tmp_key="$(mktemp)"
  printf "%s\n" "$key" >"$tmp_key"
  if ! command_exists ssh-keygen; then
    rm -f "$tmp_key"
    if is_dry_run; then
      log_warn "ssh-keygen is not available; skipping dry-run SSH public key validation."
    else
      fail_step "ssh-keygen is not available; openssh-client may not be installed."
      return $?
    fi
  elif ! ssh-keygen -l -f "$tmp_key" >/dev/null 2>&1; then
    rm -f "$tmp_key"
    fail_step "SSH public key is not a valid OpenSSH public key."
    return $?
  else
    rm -f "$tmp_key"
  fi

  if is_dry_run; then
    log_info "Would append SSH public key to $auth_file if missing"
    return 0
  fi

  q_ssh_dir="$(shell_quote "$ssh_dir")"
  q_auth_file="$(shell_quote "$auth_file")"
  run_user_shell 60 "mkdir -p $q_ssh_dir && chmod 700 $q_ssh_dir && touch $q_auth_file && chmod 600 $q_auth_file" || return $?

  if [[ "$TARGET_USER" == "root" && "${EUID:-$(id -u)}" -eq 0 ]]; then
    grep -qxF "$key" "$auth_file" 2>/dev/null && return 0
    printf "%s\n" "$key" >>"$auth_file"
  elif [[ "$TARGET_USER" == "${USER:-}" && "${EUID:-$(id -u)}" -ne 0 ]]; then
    grep -qxF "$key" "$auth_file" 2>/dev/null && return 0
    printf "%s\n" "$key" >>"$auth_file"
  else
    target_user_exec grep -qxF "$key" "$auth_file" 2>/dev/null && return 0
    # shellcheck disable=SC2016
    target_user_exec bash -c 'printf "%s\n" "$1" >> "$2"' bash "$key" "$auth_file"
  fi

  run_user_shell 60 "chmod 700 $q_ssh_dir && chmod 600 $q_auth_file"
}

configure_ssh_hardening() {
  local config
  config="# Managed by ubuntu-bootstrap
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin prohibit-password
"
  write_root_file 0644 /etc/ssh/sshd_config.d/99-ubuntu-bootstrap.conf "$config" || return $?
  run_sudo 60 sshd -t || return $?
  if has_systemd; then
    run_sudo 120 systemctl reload ssh || run_sudo 120 systemctl restart ssh
  fi
}

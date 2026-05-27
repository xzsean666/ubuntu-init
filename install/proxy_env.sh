#!/usr/bin/env bash

CLASH_VERGE_SUDOERS_PROXY_ENV_FILE="/etc/sudoers.d/90-ubuntu-bootstrap-proxy-env"
CLASH_VERGE_SUDO_ENV_KEEP='Defaults env_keep += "http_proxy https_proxy all_proxy no_proxy"'

set_clash_verge_proxy_values() {
  CLASH_VERGE_PROXY_HOST_VALUE="${CLASH_VERGE_PROXY_HOST:-127.0.0.1}"
  CLASH_VERGE_PROXY_PORT_VALUE="${CLASH_VERGE_PROXY_PORT:-7897}"
  CLASH_VERGE_HTTP_PROXY_VALUE="${CLASH_VERGE_HTTP_PROXY:-http://${CLASH_VERGE_PROXY_HOST_VALUE}:${CLASH_VERGE_PROXY_PORT_VALUE}}"
  CLASH_VERGE_HTTPS_PROXY_VALUE="${CLASH_VERGE_HTTPS_PROXY:-$CLASH_VERGE_HTTP_PROXY_VALUE}"
  CLASH_VERGE_ALL_PROXY_VALUE="${CLASH_VERGE_ALL_PROXY:-socks5://${CLASH_VERGE_PROXY_HOST_VALUE}:${CLASH_VERGE_PROXY_PORT_VALUE}}"
  CLASH_VERGE_NO_PROXY_VALUE="${CLASH_VERGE_NO_PROXY:-localhost,127.0.0.1,::1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16}"
}

validate_proxy_env_value() {
  local name="$1"
  local value="$2"
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* || "$value" == *'"'* ]]; then
    fail_step "$name contains unsupported characters for /etc/environment."
    return $?
  fi
}

validate_clash_verge_proxy_values() {
  if [[ ! "$CLASH_VERGE_PROXY_PORT_VALUE" =~ ^[0-9]+$ ]] || ((10#$CLASH_VERGE_PROXY_PORT_VALUE < 1 || 10#$CLASH_VERGE_PROXY_PORT_VALUE > 65535)); then
    fail_step "CLASH_VERGE_PROXY_PORT must be a TCP port between 1 and 65535."
    return $?
  fi

  validate_proxy_env_value CLASH_VERGE_PROXY_HOST "$CLASH_VERGE_PROXY_HOST_VALUE" || return $?
  validate_proxy_env_value CLASH_VERGE_HTTP_PROXY "$CLASH_VERGE_HTTP_PROXY_VALUE" || return $?
  validate_proxy_env_value CLASH_VERGE_HTTPS_PROXY "$CLASH_VERGE_HTTPS_PROXY_VALUE" || return $?
  validate_proxy_env_value CLASH_VERGE_ALL_PROXY "$CLASH_VERGE_ALL_PROXY_VALUE" || return $?
  validate_proxy_env_value CLASH_VERGE_NO_PROXY "$CLASH_VERGE_NO_PROXY_VALUE"
}

clash_verge_proxy_env_configured() {
  set_clash_verge_proxy_values
  validate_clash_verge_proxy_values || return 1

  local environment_content sudoers_content
  environment_content="$(read_root_file /etc/environment 2>/dev/null)" || return 1
  grep -qxF "http_proxy=\"$CLASH_VERGE_HTTP_PROXY_VALUE\"" <<<"$environment_content" || return 1
  grep -qxF "https_proxy=\"$CLASH_VERGE_HTTPS_PROXY_VALUE\"" <<<"$environment_content" || return 1
  grep -qxF "all_proxy=\"$CLASH_VERGE_ALL_PROXY_VALUE\"" <<<"$environment_content" || return 1
  grep -qxF "no_proxy=\"$CLASH_VERGE_NO_PROXY_VALUE\"" <<<"$environment_content" || return 1

  sudoers_content="$(read_root_file "$CLASH_VERGE_SUDOERS_PROXY_ENV_FILE" 2>/dev/null)" || return 1
  grep -qxF "$CLASH_VERGE_SUDO_ENV_KEEP" <<<"$sudoers_content"
}

configure_clash_verge_proxy_env() {
  if [[ "${CLASH_VERGE_CONFIGURE_PROXY_ENV:-1}" != "1" ]]; then
    log_info "Clash Verge proxy environment configuration disabled by CLASH_VERGE_CONFIGURE_PROXY_ENV."
    return 0
  fi

  set_clash_verge_proxy_values
  validate_clash_verge_proxy_values || return $?
  configure_environment_proxy_vars || return $?
  configure_sudo_proxy_env_keep
}

configure_environment_proxy_vars() {
  local environment_file="/etc/environment"
  local old new content

  if is_dry_run; then
    log_info "Would set /etc/environment proxy variables for Clash Verge on ${CLASH_VERGE_PROXY_HOST_VALUE}:${CLASH_VERGE_PROXY_PORT_VALUE}"
    return 0
  fi

  old="$(mktemp)"
  new="$(mktemp)"
  if [[ -f "$environment_file" ]]; then
    read_root_file "$environment_file" >"$old" || {
      rm -f "$old" "$new"
      return 1
    }
  else
    : >"$old"
  fi

  awk \
    -v http_proxy_value="$CLASH_VERGE_HTTP_PROXY_VALUE" \
    -v https_proxy_value="$CLASH_VERGE_HTTPS_PROXY_VALUE" \
    -v all_proxy_value="$CLASH_VERGE_ALL_PROXY_VALUE" \
    -v no_proxy_value="$CLASH_VERGE_NO_PROXY_VALUE" \
    '
BEGIN {
  order[1] = "http_proxy"
  order[2] = "https_proxy"
  order[3] = "all_proxy"
  order[4] = "no_proxy"
  values["http_proxy"] = http_proxy_value
  values["https_proxy"] = https_proxy_value
  values["all_proxy"] = all_proxy_value
  values["no_proxy"] = no_proxy_value
}
{
  key = $0
  if (match(key, /^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=/)) {
    sub(/^[[:space:]]*(export[[:space:]]+)?/, "", key)
    sub(/=.*/, "", key)
    if (key in values) {
      if (!(key in seen)) {
        print key "=\"" values[key] "\""
      }
      seen[key] = 1
      next
    }
  }
  print
}
END {
  for (i = 1; i <= 4; i++) {
    if (!(order[i] in seen)) {
      print order[i] "=\"" values[order[i]] "\""
    }
  }
}
' "$old" >"$new"

  if cmp -s "$old" "$new"; then
    log_info "/etc/environment proxy variables are already configured for Clash Verge."
    rm -f "$old" "$new"
    return 0
  fi

  if [[ -f "$environment_file" ]]; then
    run_sudo 60 cp "$environment_file" "$environment_file.bak.$(date +%Y%m%d%H%M%S)" || {
      rm -f "$old" "$new"
      return 1
    }
  fi

  content="$(<"$new")"
  write_root_file 0644 "$environment_file" "$content"
  local rc=$?
  rm -f "$old" "$new"
  return "$rc"
}

run_visudo_check() {
  local file="$1"
  if command_exists visudo; then
    run_sudo 60 visudo -cf "$file"
  elif [[ -x /usr/sbin/visudo ]]; then
    run_sudo 60 /usr/sbin/visudo -cf "$file"
  else
    fail_step "visudo is not available; refusing to write sudoers proxy environment config."
    return $?
  fi
}

configure_sudo_proxy_env_keep() {
  local content tmp
  content="# Managed by ubuntu-bootstrap
$CLASH_VERGE_SUDO_ENV_KEEP
"

  if is_dry_run; then
    log_info "Would write $CLASH_VERGE_SUDOERS_PROXY_ENV_FILE so sudo keeps proxy environment variables."
    return 0
  fi

  tmp="$(mktemp)"
  printf "%s" "$content" >"$tmp"
  run_visudo_check "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  rm -f "$tmp"

  write_root_file 0440 "$CLASH_VERGE_SUDOERS_PROXY_ENV_FILE" "$content" || return $?
  run_visudo_check /etc/sudoers
}

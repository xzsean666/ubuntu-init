#!/usr/bin/env bash
# shellcheck disable=SC2034

STEP_SKIPPED=75
APT_UPDATED=0
APT_MIRROR_CONFIGURED=0
COUNTRY_CODE="${UBUNTU_BOOTSTRAP_COUNTRY:-}"
TARGET_USER=""
TARGET_HOME=""
STEP_RESULT_REASON=""
LOG_TO_FILE=0

COMMAND_TIMEOUT="${COMMAND_TIMEOUT:-900}"
DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-300}"
RETRY_COUNT="${RETRY_COUNT:-2}"
UBUNTU_APT_MIRROR="${UBUNTU_APT_MIRROR:-https://mirrors.tuna.tsinghua.edu.cn/ubuntu}"

DOCKER_REGISTRY_MIRROR_URLS=(
  "https://docker.1ms.run"
  "https://docker.m.daocloud.io"
  "https://docker.xuanyuan.me"
)
DOCKER_REGISTRY_MIRROR_HOSTS=(
  "docker.1ms.run"
  "docker.m.daocloud.io"
  "docker.xuanyuan.me"
)

declare -a OK_STEPS=()
declare -a SKIPPED_STEPS=()
declare -a FAILED_STEPS=()

is_dry_run() {
  [[ "${DRY_RUN:-0}" == "1" ]]
}

quote_cmd() {
  printf "%q " "$@"
}

timestamp() {
  date "+%Y-%m-%d %H:%M:%S"
}

log_line() {
  local level="$1"
  shift
  local line
  line="[$(timestamp)] [$level] $*"
  echo "$line"
  if [[ "$LOG_TO_FILE" == "1" && -n "${LOG_FILE:-}" ]]; then
    printf "%s\n" "$line" >>"$LOG_FILE" 2>/dev/null || true
  fi
}

log_info() {
  log_line INFO "$@"
}

log_warn() {
  log_line WARN "$@"
}

log_error() {
  log_line ERROR "$@"
}

log_debug() {
  [[ "${DEBUG:-0}" == "1" ]] && log_line DEBUG "$@"
}

detect_target_user() {
  local passwd_entry
  if [[ -n "${UBUNTU_BOOTSTRAP_USER:-}" ]]; then
    TARGET_USER="$UBUNTU_BOOTSTRAP_USER"
  elif [[ "${EUID:-$(id -u)}" -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER:-}" != "root" ]]; then
    TARGET_USER="$SUDO_USER"
  else
    TARGET_USER="${USER:-$(id -un)}"
  fi

  passwd_entry="$(getent passwd "$TARGET_USER" || true)"
  if [[ -z "$passwd_entry" ]]; then
    echo "Target user does not exist: $TARGET_USER" >&2
    return 2
  fi
  TARGET_HOME="$(cut -d: -f6 <<<"$passwd_entry")"
  if [[ -z "$TARGET_HOME" ]]; then
    echo "Could not determine home directory for target user: $TARGET_USER" >&2
    return 2
  fi
}

bootstrap_init() {
  local script_dir="$1"
  detect_target_user || return $?

  if [[ -z "${LOG_FILE:-}" ]]; then
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
      LOG_FILE="/var/log/ubuntu-bootstrap.log"
    else
      LOG_FILE="$script_dir/logs/ubuntu-bootstrap.log"
    fi
  fi

  if mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null && : >"$LOG_FILE" 2>/dev/null; then
    LOG_TO_FILE=1
  else
    echo "Warning: could not write log file $LOG_FILE; falling back to repository logs." >&2
    LOG_FILE="$script_dir/logs/ubuntu-bootstrap.log"
    if mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null && : >"$LOG_FILE" 2>/dev/null; then
      LOG_TO_FILE=1
    else
      echo "Warning: file logging disabled; could not write fallback log file $LOG_FILE." >&2
      LOG_FILE=""
      LOG_TO_FILE=0
    fi
  fi

  log_info "Ubuntu Bootstrap started"
  if [[ "$LOG_TO_FILE" == "1" ]]; then
    log_info "Log file: $LOG_FILE"
  else
    log_warn "Log file: disabled"
  fi
}

has_item() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

dedupe_and_filter_modules() {
  local -a out=()
  local module
  for module in "$@"; do
    [[ -z "$module" ]] && continue
    if has_item "$module" "${SKIP_MODULES[@]:-}"; then
      continue
    fi
    if ! has_item "$module" "${out[@]:-}"; then
      out+=("$module")
    fi
  done
  if ((${#out[@]} > 0)); then
    printf "%s\n" "${out[@]}"
  fi
}

skip_step() {
  STEP_RESULT_REASON="$*"
  return "$STEP_SKIPPED"
}

fail_step() {
  STEP_RESULT_REASON="$*"
  return 1
}

require_non_root_target() {
  local name="$1"
  if [[ "$TARGET_USER" == "root" && "${ALLOW_ROOT_USER_TOOLS:-0}" != "1" ]]; then
    fail_step "$name is installed per user; run via sudo from your user, set UBUNTU_BOOTSTRAP_USER, or set ALLOW_ROOT_USER_TOOLS=1."
    return $?
  fi
  return 0
}

record_ok() {
  OK_STEPS+=("$1")
}

record_skipped() {
  SKIPPED_STEPS+=("$1|$2")
}

record_failed() {
  FAILED_STEPS+=("$1|$2")
}

run_step() {
  local name="$1"
  local func="$2"
  local rc
  STEP_RESULT_REASON=""

  log_info "================================"
  log_info "Starting: $name"
  "$func"
  rc=$?

  if [[ "$rc" -eq 0 ]]; then
    record_ok "$name"
    log_info "[OK] $name"
    return 0
  elif [[ "$rc" -eq "$STEP_SKIPPED" ]]; then
    record_skipped "$name" "${STEP_RESULT_REASON:-skipped}"
    log_warn "[SKIPPED] $name - ${STEP_RESULT_REASON:-skipped}"
    return 0
  else
    record_failed "$name" "${STEP_RESULT_REASON:-exit code $rc}"
    log_error "[FAILED] $name - ${STEP_RESULT_REASON:-exit code $rc}"
    return "$rc"
  fi
}

run_cmd() {
  local seconds="$1"
  shift
  local display
  display="$(quote_cmd "$@")"
  log_info "+ $display"

  if is_dry_run; then
    return 0
  fi

  local attempt rc
  for ((attempt = 1; attempt <= RETRY_COUNT; attempt++)); do
    if [[ "$LOG_TO_FILE" == "1" && -n "${LOG_FILE:-}" ]]; then
      timeout --foreground "$seconds" "$@" 2>&1 | tee -a "$LOG_FILE"
      local -a pipe_status=("${PIPESTATUS[@]}")
      rc="${pipe_status[0]}"
      if [[ "$rc" -eq 0 && "${pipe_status[1]}" -ne 0 ]]; then
        rc="${pipe_status[1]}"
      fi
    else
      timeout --foreground "$seconds" "$@"
      rc=$?
    fi

    if [[ "$rc" -eq 0 ]]; then
      return 0
    fi
    if ((attempt < RETRY_COUNT)); then
      log_warn "Command failed with exit code $rc, retrying ($attempt/$RETRY_COUNT): $display"
      sleep 2
    fi
  done
  return "$rc"
}

run_shell() {
  local seconds="$1"
  shift
  run_cmd "$seconds" bash -lc "$*"
}

run_sudo() {
  local seconds="$1"
  shift
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    run_cmd "$seconds" "$@"
  else
    run_cmd "$seconds" sudo "$@"
  fi
}

run_sudo_shell() {
  local seconds="$1"
  shift
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    run_cmd "$seconds" bash -lc "$*"
  else
    run_cmd "$seconds" sudo bash -lc "$*"
  fi
}

run_user_cmd() {
  local seconds="$1"
  shift
  if [[ "$TARGET_USER" == "root" && "${EUID:-$(id -u)}" -eq 0 ]]; then
    run_cmd "$seconds" "$@"
  elif [[ "$TARGET_USER" == "${USER:-}" && "${EUID:-$(id -u)}" -ne 0 ]]; then
    run_cmd "$seconds" "$@"
  elif [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    run_cmd "$seconds" runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" USER="$TARGET_USER" LOGNAME="$TARGET_USER" "$@"
  else
    run_cmd "$seconds" sudo -H -u "$TARGET_USER" "$@"
  fi
}

run_user_shell() {
  local seconds="$1"
  shift
  local script="$*"
  run_user_cmd "$seconds" bash -lc "$script"
}

target_user_exec() {
  if [[ "$TARGET_USER" == "root" && "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif [[ "$TARGET_USER" == "${USER:-}" && "${EUID:-$(id -u)}" -ne 0 ]]; then
    "$@"
  elif [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    runuser -u "$TARGET_USER" -- env HOME="$TARGET_HOME" USER="$TARGET_USER" LOGNAME="$TARGET_USER" "$@"
  else
    sudo -H -u "$TARGET_USER" "$@"
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

apt_package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -qx "install ok installed"
}

filter_missing_apt_packages() {
  local package
  for package in "$@"; do
    apt_package_installed "$package" || printf "%s\n" "$package"
  done
}

has_systemd() {
  [[ -d /run/systemd/system ]] && command_exists systemctl
}

apt_update() {
  configure_apt_mirror_if_needed || return $?
  run_sudo 1800 env DEBIAN_FRONTEND=noninteractive apt-get update || return $?
  APT_UPDATED=1
}

apt_install() {
  (($# > 0)) || return 0
  local -a missing=()
  if ! is_dry_run; then
    mapfile -t missing < <(filter_missing_apt_packages "$@")
    if ((${#missing[@]} == 0)); then
      log_info "Skipping apt install; packages already installed: $*"
      return 0
    fi
    if ((${#missing[@]} < $#)); then
      log_info "Skipping already installed apt packages; installing missing packages: ${missing[*]}"
    fi
    set -- "${missing[@]}"
  fi
  if [[ "$APT_UPDATED" != "1" ]]; then
    apt_update || return $?
  fi
  run_sudo 1800 env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@"
}

download_to() {
  local url="$1"
  local dest="$2"
  run_cmd "$DOWNLOAD_TIMEOUT" curl -fsSL --retry 2 --retry-delay 2 --connect-timeout 10 --max-time "$DOWNLOAD_TIMEOUT" -o "$dest" "$url"
}

install_deb_from_url() {
  local name="$1"
  local url="$2"
  local expected_sha256="${3:-}"
  local tmpdir deb
  if is_dry_run; then
    if [[ -n "$expected_sha256" ]]; then
      log_info "Would download, verify SHA256, and install $name from $url"
    else
      log_info "Would download and install $name from $url"
    fi
    return 0
  fi
  tmpdir="$(mktemp -d)"
  deb="$tmpdir/${name}.deb"
  download_to "$url" "$deb" || {
    rm -rf "$tmpdir"
    return 1
  }
  if [[ -n "$expected_sha256" ]]; then
    printf "%s  %s\n" "$expected_sha256" "$deb" | sha256sum -c - || {
      rm -rf "$tmpdir"
      return 1
    }
  fi
  run_sudo 1800 env DEBIAN_FRONTEND=noninteractive apt-get install -y "$deb"
  local rc=$?
  rm -rf "$tmpdir"
  return "$rc"
}

run_downloaded_user_script() {
  local url="$1"
  local interpreter="$2"
  local prefix="${3:-}"
  local tmp q_tmp rc

  if is_dry_run; then
    log_info "Would download $url and run it with $interpreter as $TARGET_USER"
    return 0
  fi

  tmp="$(mktemp)"
  download_to "$url" "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  chmod 0644 "$tmp"
  q_tmp="$(shell_quote "$tmp")"
  run_user_shell "$DOWNLOAD_TIMEOUT" "${prefix}${interpreter} $q_tmp"
  rc=$?
  rm -f "$tmp"
  return "$rc"
}

write_root_file() {
  local mode="$1"
  local target="$2"
  local content="$3"
  local tmp

  if is_dry_run; then
    log_info "Would write $target"
    log_debug "$content"
    return 0
  fi

  tmp="$(mktemp)"
  printf "%s" "$content" >"$tmp"
  run_sudo 60 install -D -m "$mode" "$tmp" "$target"
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

shell_quote() {
  printf "%q" "$1"
}

read_root_file() {
  local path="$1"
  if [[ -r "$path" ]]; then
    cat "$path"
  elif [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    cat "$path"
  else
    sudo cat "$path"
  fi
}

append_user_file_if_missing() {
  local file="$1"
  local marker="$2"
  local content="$3"
  local tmp q_dir q_file

  if is_dry_run; then
    log_info "Would append block to $file if marker is missing: $marker"
    return 0
  fi

  q_dir="$(shell_quote "$(dirname "$file")")"
  q_file="$(shell_quote "$file")"
  run_user_shell 60 "mkdir -p $q_dir && touch $q_file" || return $?

  if [[ "$TARGET_USER" == "root" && "${EUID:-$(id -u)}" -eq 0 ]]; then
    grep -Fq "$marker" "$file" 2>/dev/null && return 0
  elif [[ "$TARGET_USER" == "${USER:-}" && "${EUID:-$(id -u)}" -ne 0 ]]; then
    grep -Fq "$marker" "$file" 2>/dev/null && return 0
  else
    target_user_exec grep -Fq "$marker" "$file" 2>/dev/null && return 0
  fi

  tmp="$(mktemp)"
  printf "\n%s\n" "$content" >"$tmp"
  chmod 0644 "$tmp"
  if [[ "$TARGET_USER" == "root" && "${EUID:-$(id -u)}" -eq 0 ]]; then
    cat "$tmp" >>"$file"
  elif [[ "$TARGET_USER" == "${USER:-}" && "${EUID:-$(id -u)}" -ne 0 ]]; then
    cat "$tmp" >>"$file"
  else
    # shellcheck disable=SC2016
    target_user_exec bash -c 'cat "$1" >> "$2"' bash "$tmp" "$file"
  fi
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

ensure_country_detected() {
  if [[ "$NO_CHINA_MIRRORS" == "1" ]]; then
    COUNTRY_CODE="disabled"
    return 0
  fi
  if [[ "$FORCE_CHINA_MIRRORS" == "1" ]]; then
    COUNTRY_CODE="CN"
    return 0
  fi
  if [[ -n "$COUNTRY_CODE" ]]; then
    return 0
  fi
  if [[ "$SKIP_NETWORK_CHECK" == "1" ]]; then
    COUNTRY_CODE="unknown"
    return 0
  fi
  if is_dry_run; then
    COUNTRY_CODE="unknown"
    return 0
  fi

  local country=""
  if command_exists curl; then
    country="$(timeout 8 curl -fsSL --connect-timeout 4 --max-time 6 https://ipapi.co/country/ 2>/dev/null | tr -dc '[:upper:]' | head -c 2 || true)"
    if [[ -z "$country" ]]; then
      country="$(timeout 8 curl -fsSL --connect-timeout 4 --max-time 6 https://ifconfig.co/country-iso 2>/dev/null | tr -dc '[:upper:]' | head -c 2 || true)"
    fi
  elif command_exists wget; then
    country="$(timeout 8 wget -qO- https://ipapi.co/country/ 2>/dev/null | tr -dc '[:upper:]' | head -c 2 || true)"
  fi

  COUNTRY_CODE="${country:-unknown}"
  log_info "Detected network country: $COUNTRY_CODE"
}

is_china_network() {
  ensure_country_detected
  [[ "$COUNTRY_CODE" == "CN" ]]
}

redetect_country_if_unknown() {
  if [[ "$COUNTRY_CODE" == "unknown" && "$SKIP_NETWORK_CHECK" != "1" && "$NO_CHINA_MIRRORS" != "1" && "$FORCE_CHINA_MIRRORS" != "1" ]] && ! is_dry_run; then
    COUNTRY_CODE=""
  fi
}

configure_apt_mirror_if_needed() {
  [[ "${NO_APT_MIRROR:-0}" == "1" ]] && return 0
  [[ "$APT_MIRROR_CONFIGURED" == "1" ]] && return 0
  redetect_country_if_unknown
  is_china_network || {
    log_info "China mirrors not enabled for apt (country=$COUNTRY_CODE)."
    [[ "$COUNTRY_CODE" != "unknown" ]] && APT_MIRROR_CONFIGURED=1
    return 0
  }

  local file existing updated mirror_escaped
  local -a files=(
    "/etc/apt/sources.list"
    "/etc/apt/sources.list.d/ubuntu.sources"
  )

  if [[ "$UBUNTU_APT_MIRROR" == *'|'* || "$UBUNTU_APT_MIRROR" == *\\* || "$UBUNTU_APT_MIRROR" == *$'\n'* ]]; then
    log_error "UBUNTU_APT_MIRROR contains unsupported characters for safe replacement: $UBUNTU_APT_MIRROR"
    return 1
  fi

  local ports_mirror=""
  if [[ "$UBUNTU_APT_MIRROR" == *"mirrors.tuna.tsinghua.edu.cn/ubuntu"* ]]; then
    ports_mirror="https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports"
  elif [[ "$UBUNTU_APT_MIRROR" == *"mirrors.ustc.edu.cn/ubuntu"* ]]; then
    ports_mirror="https://mirrors.ustc.edu.cn/ubuntu-ports"
  elif [[ "$UBUNTU_APT_MIRROR" == *"mirrors.aliyun.com/ubuntu"* ]]; then
    ports_mirror="https://mirrors.aliyun.com/ubuntu-ports"
  else
    if [[ "$UBUNTU_APT_MIRROR" == */ubuntu ]]; then
      ports_mirror="${UBUNTU_APT_MIRROR}-ports"
    else
      ports_mirror="$UBUNTU_APT_MIRROR"
    fi
  fi

  for file in "${files[@]}"; do
    [[ -f "$file" ]] || continue
    existing="$(read_root_file "$file")" || continue
    if ! grep -Eq 'https?://([a-z]{2}\.)?archive\.ubuntu\.com/ubuntu/?|https?://security\.ubuntu\.com/ubuntu/?|https?://ports\.ubuntu\.com/ubuntu-ports/?' <<<"$existing"; then
      log_info "Skipping apt mirror rewrite for $file; no default Ubuntu archive or ports URLs found."
      continue
    fi

    mirror_escaped="${UBUNTU_APT_MIRROR%/}/"
    mirror_escaped="${mirror_escaped//&/\\&}"

    local ports_mirror_escaped
    ports_mirror_escaped="${ports_mirror%/}/"
    ports_mirror_escaped="${ports_mirror_escaped//&/\\&}"

    updated="$(sed -E \
      -e "s|https?://([a-z]{2}\\.)?archive\\.ubuntu\\.com/ubuntu/?|$mirror_escaped|g" \
      -e "s|https?://security\\.ubuntu\\.com/ubuntu/?|$mirror_escaped|g" \
      -e "s|https?://ports\\.ubuntu\\.com/ubuntu-ports/?|$ports_mirror_escaped|g" \
      <<<"$existing")"

    if [[ "$updated" == "$existing" ]]; then
      continue
    fi

    if is_dry_run; then
      log_info "Would rewrite Ubuntu apt mirror in $file to $UBUNTU_APT_MIRROR"
      continue
    fi

    run_sudo 60 cp "$file" "$file.bak.$(date +%Y%m%d%H%M%S)" || return $?
    write_root_file 0644 "$file" "$updated" || return $?
    APT_UPDATED=0
    log_info "Rewrote Ubuntu apt mirror in $file to $UBUNTU_APT_MIRROR"
  done
  APT_MIRROR_CONFIGURED=1
}

github_latest_asset_url() {
  local repo="$1"
  local pattern="$2"
  local tmp
  tmp="$(mktemp)"
  download_to "https://api.github.com/repos/${repo}/releases/latest" "$tmp" || {
    rm -f "$tmp"
    return 1
  }
  python3 - "$tmp" "$pattern" <<'PY'
import json, re, sys
path, pattern = sys.argv[1], sys.argv[2]
data = json.load(open(path, encoding="utf-8"))
regex = re.compile(pattern)
for asset in data.get("assets", []):
    name = asset.get("name", "")
    url = asset.get("browser_download_url", "")
    if url and regex.search(name):
        print(url)
        sys.exit(0)
sys.exit(1)
PY
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

print_summary() {
  echo
  echo "================================"
  if is_dry_run; then
    echo "Ubuntu Bootstrap Dry Run Completed"
  else
    echo "Ubuntu Bootstrap Completed"
  fi
  echo "================================"
  echo
  if is_dry_run; then
    echo "Planned:"
  else
    echo "Installed:"
  fi
  if [[ -z "${OK_STEPS[*]-}" ]]; then
    echo " - (none)"
  else
    local item
    for item in "${OK_STEPS[@]}"; do
      if is_dry_run; then
        echo " - [DRY-RUN OK] $item"
      else
        echo " - [OK] $item"
      fi
    done
  fi

  echo
  echo "Skipped:"
  if [[ -z "${SKIPPED_STEPS[*]-}" ]]; then
    echo " - (none)"
  else
    local entry name reason
    for entry in "${SKIPPED_STEPS[@]}"; do
      IFS='|' read -r name reason <<<"$entry"
      echo " - [SKIPPED] $name - $reason"
    done
  fi

  echo
  echo "Failed:"
  if [[ -z "${FAILED_STEPS[*]-}" ]]; then
    echo " - (none)"
  else
    local entry name reason
    for entry in "${FAILED_STEPS[@]}"; do
      IFS='|' read -r name reason <<<"$entry"
      echo " - [FAILED] $name - $reason"
      echo "   log: $LOG_FILE"
    done
  fi

  echo
  echo "Logs:"
  if [[ "$LOG_TO_FILE" == "1" ]]; then
    echo " $LOG_FILE"
  else
    echo " disabled"
  fi
}

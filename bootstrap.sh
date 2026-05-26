#!/usr/bin/env bash
# shellcheck disable=SC2034
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MODE=""
DRY_RUN="${DRY_RUN:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
DEBUG="${DEBUG:-0}"
STRICT="${STRICT:-0}"
SSH_PUBLIC_KEY="${SSH_PUBLIC_KEY:-}"
HARDEN_SSH="${HARDEN_SSH:-0}"
FORCE_CHINA_MIRRORS="${FORCE_CHINA_MIRRORS:-0}"
NO_CHINA_MIRRORS="${NO_CHINA_MIRRORS:-0}"
SKIP_NETWORK_CHECK="${SKIP_NETWORK_CHECK:-0}"
LOG_FILE="${UBUNTU_BOOTSTRAP_LOG:-}"

declare -a EXPLICIT_MODULES=()
declare -a ONLY_MODULES=()
declare -a SKIP_MODULES=()
VALID_MODULES=(
  base ssh docker node pnpm python uv gh codex claude antigravity
  fcitx5 chrome vscode baota slack wechat clash youdao navicat
)

usage() {
  cat <<'EOF'
Ubuntu Bootstrap

Usage:
  ./bootstrap.sh --desktop [options]
  ./bootstrap.sh --server [options]
  ./bootstrap.sh --only docker,node,pnpm --dry-run

Modes:
  --desktop                 Install MVP desktop developer environment
  --server                  Install server baseline, excluding BaoTa by default

Common options:
  --ssh-key <key>           Append a public key to the target user's authorized_keys
  --harden-ssh              Disable SSH password login and root password login
  --dry-run                 Print commands without changing the system
  --yes, -y                 Assume yes for supported installers
  --strict                  Exit non-zero if any step fails
  --debug                   Enable debug logging
  --log-file <path>         Override log path
  --force-china-mirrors     Force China mirror configuration
  --no-china-mirrors        Disable China mirror configuration
  --skip-network-check      Do not detect public IP country
  --only a,b,c              Run only selected module ids
  --skip a,b,c              Skip selected module ids from the selected mode
  --help                    Show this help

Module flags:
  --base --ssh --docker --node --pnpm --python --uv --gh
  --codex --claude --antigravity --ai
  --fcitx5 --chrome --vscode
  --baota
  --slack --wechat --clash --youdao --navicat
  --all-desktop-extras

Module ids:
  base ssh docker node pnpm python uv gh codex claude antigravity
  fcitx5 chrome vscode baota slack wechat clash youdao navicat
EOF
}

append_csv() {
  local -n target="$1"
  local value="$2"
  local item
  local -a _items
  IFS=',' read -r -a _items <<<"$value"
  for item in "${_items[@]}"; do
    item="$(trim_ws "$item")"
    [[ -n "$item" ]] && target+=("$item")
  done
}

trim_ws() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf "%s" "$value"
}

add_module() {
  EXPLICIT_MODULES+=("$1")
}

while (($#)); do
  case "$1" in
    --desktop) MODE="desktop" ;;
    --server) MODE="server" ;;
    --ssh-key)
      shift
      [[ $# -gt 0 ]] || { echo "--ssh-key requires a value" >&2; exit 2; }
      SSH_PUBLIC_KEY="$1"
      ;;
    --ssh-key=*) SSH_PUBLIC_KEY="${1#*=}" ;;
    --harden-ssh) HARDEN_SSH=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --yes|-y) ASSUME_YES=1 ;;
    --strict) STRICT=1 ;;
    --debug) DEBUG=1 ;;
    --log-file)
      shift
      [[ $# -gt 0 ]] || { echo "--log-file requires a value" >&2; exit 2; }
      LOG_FILE="$1"
      ;;
    --force-china-mirrors) FORCE_CHINA_MIRRORS=1 ;;
    --no-china-mirrors) NO_CHINA_MIRRORS=1 ;;
    --skip-network-check) SKIP_NETWORK_CHECK=1 ;;
    --only)
      shift
      [[ $# -gt 0 ]] || { echo "--only requires a comma separated list" >&2; exit 2; }
      append_csv ONLY_MODULES "$1"
      ;;
    --only=*) append_csv ONLY_MODULES "${1#*=}" ;;
    --skip)
      shift
      [[ $# -gt 0 ]] || { echo "--skip requires a comma separated list" >&2; exit 2; }
      append_csv SKIP_MODULES "$1"
      ;;
    --skip=*) append_csv SKIP_MODULES "${1#*=}" ;;
    --base) add_module base ;;
    --ssh) add_module ssh ;;
    --docker) add_module docker ;;
    --node) add_module node ;;
    --pnpm) add_module pnpm ;;
    --python) add_module python ;;
    --uv) add_module uv ;;
    --gh) add_module gh ;;
    --codex) add_module codex ;;
    --claude) add_module claude ;;
    --antigravity) add_module antigravity ;;
    --ai)
      add_module codex
      add_module claude
      add_module antigravity
      ;;
    --fcitx5) add_module fcitx5 ;;
    --chrome) add_module chrome ;;
    --vscode) add_module vscode ;;
    --baota) add_module baota ;;
    --slack) add_module slack ;;
    --wechat) add_module wechat ;;
    --clash) add_module clash ;;
    --youdao) add_module youdao ;;
    --navicat) add_module navicat ;;
    --all-desktop-extras)
      add_module slack
      add_module wechat
      add_module clash
      add_module youdao
      add_module navicat
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ "$FORCE_CHINA_MIRRORS" == "1" && "$NO_CHINA_MIRRORS" == "1" ]]; then
  echo "--force-china-mirrors and --no-china-mirrors cannot be used together." >&2
  exit 2
fi

source_required() {
  local file="$1"
  if [[ ! -r "$file" ]]; then
    echo "Missing required file: $file" >&2
    exit 2
  fi
  # shellcheck source=/dev/null
  source "$file" || {
    echo "Failed to load required file: $file" >&2
    exit 2
  }
}

is_valid_module() {
  has_item "$1" "${VALID_MODULES[@]}"
}

module_requires_non_root() {
  case "$1" in
    node|pnpm|python|uv|codex|claude|antigravity|fcitx5) return 0 ;;
    *) return 1 ;;
  esac
}

source_required "$SCRIPT_DIR/lib/common.sh"
source_required "$SCRIPT_DIR/install/base.sh"
source_required "$SCRIPT_DIR/install/ssh.sh"
source_required "$SCRIPT_DIR/install/docker.sh"
source_required "$SCRIPT_DIR/install/node.sh"
source_required "$SCRIPT_DIR/install/python.sh"
source_required "$SCRIPT_DIR/install/gh.sh"
source_required "$SCRIPT_DIR/install/ai_cli.sh"
source_required "$SCRIPT_DIR/install/desktop.sh"
source_required "$SCRIPT_DIR/install/baota.sh"
source_required "$SCRIPT_DIR/install/desktop_extras.sh"

build_plan() {
  local -a plan=()
  local -a filtered=()
  local module

  for module in "${ONLY_MODULES[@]}" "${EXPLICIT_MODULES[@]}" "${SKIP_MODULES[@]}"; do
    if [[ -n "$module" ]] && ! is_valid_module "$module"; then
      echo "Unknown module id: $module" >&2
      return 2
    fi
  done

  case "$MODE" in
    desktop)
      plan=(base ssh docker node pnpm python uv gh codex claude antigravity fcitx5 chrome vscode)
      ;;
    server)
      plan=(base ssh docker gh)
      ;;
    "")
      plan=()
      ;;
    *)
      echo "Unsupported mode: $MODE" >&2
      return 2
      ;;
  esac

  if ((${#ONLY_MODULES[@]} > 0)); then
    plan=("${ONLY_MODULES[@]}")
  fi

  if ((${#EXPLICIT_MODULES[@]} > 0)); then
    plan+=("${EXPLICIT_MODULES[@]}")
  fi

  if ((${#plan[@]} == 0)); then
    echo "No mode or modules selected." >&2
    usage >&2
    return 2
  fi

  mapfile -t filtered < <(dedupe_and_filter_modules "${plan[@]}")
  if ((${#filtered[@]} == 0)); then
    echo "No modules left after applying --skip filters." >&2
    return 2
  fi
  for module in "${filtered[@]}"; do
    if ! is_valid_module "$module"; then
      echo "Unknown module id: $module" >&2
      return 2
    fi
  done
  printf "%s\n" "${filtered[@]}"
}

run_module() {
  local module="$1"
  case "$module" in
    base) run_step "Base system" install_base ;;
    ssh) run_step "SSH server" install_ssh ;;
    docker) run_step "Docker" install_docker ;;
    node) run_step "Node.js" install_node ;;
    pnpm) run_step "pnpm" install_pnpm ;;
    python) run_step "Python" install_python ;;
    uv) run_step "uv" install_uv ;;
    gh) run_step "GitHub CLI" install_gh ;;
    codex) run_step "Codex CLI" install_codex_cli ;;
    claude) run_step "Claude Code CLI" install_claude_cli ;;
    antigravity) run_step "Antigravity CLI" install_antigravity_cli ;;
    fcitx5) run_step "Fcitx5 Chinese input" install_fcitx5 ;;
    chrome) run_step "Google Chrome" install_chrome ;;
    vscode) run_step "VS Code" install_vscode ;;
    baota) run_step "BaoTa Panel" install_baota ;;
    slack) run_step "Slack" install_slack ;;
    wechat) run_step "WeChat" install_wechat ;;
    clash) run_step "Clash Verge" install_clash_verge ;;
    youdao) run_step "Youdao Note" install_youdao_note ;;
    navicat) run_step "Navicat Premium" install_navicat ;;
    *)
      record_failed "$module" "Unknown module id"
      return 2
      ;;
  esac
}

main() {
  bootstrap_init "$SCRIPT_DIR" || return $?

  local -a plan
  local plan_output
  if ! plan_output="$(build_plan)"; then
    return 2
  fi
  mapfile -t plan <<<"$plan_output"

  log_info "Selected mode: ${MODE:-custom}"
  log_info "Target user: $TARGET_USER"
  log_info "Plan: ${plan[*]}"
  if is_dry_run; then
    log_warn "Dry-run mode: commands will be logged but not executed."
  fi

  if [[ "$TARGET_USER" == "root" && "${ALLOW_ROOT_USER_TOOLS:-0}" != "1" ]]; then
    local module
    for module in "${plan[@]}"; do
      if module_requires_non_root "$module"; then
        log_error "$module is a per-user module and target user is root. Set UBUNTU_BOOTSTRAP_USER or ALLOW_ROOT_USER_TOOLS=1."
        return 2
      fi
    done
  fi

  local module
  local fatal_rc=0
  local rc
  for module in "${plan[@]}"; do
    run_module "$module" || {
      rc=$?
      [[ "$fatal_rc" -eq 0 ]] && fatal_rc="$rc"
    }
  done

  print_summary

  if [[ "$fatal_rc" -ne 0 ]]; then
    return "$fatal_rc"
  fi
  if [[ "$STRICT" == "1" && -n "${FAILED_STEPS[*]-}" ]]; then
    return 1
  fi
  return 0
}

main "$@"

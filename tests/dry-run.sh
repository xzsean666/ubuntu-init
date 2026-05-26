#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mapfile -t scripts < <(find "$ROOT_DIR" -type f -name "*.sh" -not -path "$ROOT_DIR/.git/*" | sort)
for script in "${scripts[@]}"; do
  bash -n "$script"
done

run_ok() {
  local name="$1"
  shift
  local output="$TMP_DIR/${name}.out"
  "$@" >"$output" 2>&1
  if grep -q '\[FAILED\]' "$output"; then
    cat "$output"
    echo "dry-run case has failed steps: $name" >&2
    return 1
  fi
}

run_fail() {
  local name="$1"
  shift
  local output="$TMP_DIR/${name}.out"
  if "$@" >"$output" 2>&1; then
    cat "$output"
    echo "dry-run case unexpectedly passed: $name" >&2
    return 1
  fi
}

ssh-keygen -q -t ed25519 -N '' -f "$TMP_DIR/test_key"

run_ok desktop-cn env UBUNTU_BOOTSTRAP_COUNTRY=CN "$ROOT_DIR/bootstrap.sh" --desktop --dry-run --strict --log-file "$TMP_DIR/test-desktop.log"
run_ok server-cn env UBUNTU_BOOTSTRAP_COUNTRY=CN "$ROOT_DIR/bootstrap.sh" --server --dry-run --strict --log-file "$TMP_DIR/test-server.log"
run_ok server-baota env UBUNTU_BOOTSTRAP_COUNTRY=CN "$ROOT_DIR/bootstrap.sh" --server --baota --dry-run --strict --log-file "$TMP_DIR/test-server-baota.log"
run_ok custom-us env UBUNTU_BOOTSTRAP_COUNTRY=US "$ROOT_DIR/bootstrap.sh" --only docker,node,pnpm,python,uv,gh,codex,claude,antigravity --dry-run --strict --log-file "$TMP_DIR/test-custom.log"
run_ok extras env UBUNTU_BOOTSTRAP_COUNTRY=US "$ROOT_DIR/bootstrap.sh" --only slack,wechat,clash,youdao,navicat --dry-run --strict --log-file "$TMP_DIR/test-extras.log"
run_ok direct-debs env UBUNTU_BOOTSTRAP_COUNTRY=US ALLOW_UNVERIFIED_DEB=1 YOUDAO_DEB_URL=https://example.com/youdao.deb NAVICAT_DEB_URL=https://example.com/navicat.deb "$ROOT_DIR/bootstrap.sh" --only youdao,navicat --dry-run --strict --log-file "$TMP_DIR/test-direct-debs.log"
run_ok ssh-key env UBUNTU_BOOTSTRAP_COUNTRY=US "$ROOT_DIR/bootstrap.sh" --only ssh --ssh-key "$(cat "$TMP_DIR/test_key.pub")" --dry-run --strict --log-file "$TMP_DIR/test-ssh-key.log"

run_fail invalid-module "$ROOT_DIR/bootstrap.sh" --only does-not-exist --dry-run --log-file "$TMP_DIR/test-invalid.log"
run_fail invalid-skip "$ROOT_DIR/bootstrap.sh" --only docker --skip does-not-exist --dry-run --log-file "$TMP_DIR/test-invalid-skip.log"
run_fail invalid-ssh-key "$ROOT_DIR/bootstrap.sh" --only ssh --ssh-key "not-a-valid-key" --dry-run --log-file "$TMP_DIR/test-invalid-ssh-key.log"
run_fail root-user-tools env UBUNTU_BOOTSTRAP_USER=root "$ROOT_DIR/bootstrap.sh" --only node --dry-run --log-file "$TMP_DIR/test-root-user-tools.log"
run_fail mirror-conflict "$ROOT_DIR/bootstrap.sh" --desktop --dry-run --force-china-mirrors --no-china-mirrors --log-file "$TMP_DIR/test-mirror-conflict.log"

echo "dry-run tests passed"

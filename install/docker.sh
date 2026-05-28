#!/usr/bin/env bash
# shellcheck disable=SC2034

install_docker() {
  if ! is_dry_run && docker_ready; then
    log_info "Skipping Docker Engine install; Docker, compose, and buildx are already available."
    if docker_group_ready && ! is_china_network; then
      skip_step "Docker, compose, and buildx are already installed."
      return $?
    fi
  else
    install_docker_engine || return $?
  fi

  configure_docker_group || return $?

  if is_china_network; then
    configure_docker_daemon_mirrors || return $?
    configure_buildkit_mirrors || return $?
    restart_docker || log_warn "Docker restart failed; mirror config may apply after a manual restart."
    configure_buildx_builder || return $?
  else
    log_info "China mirrors not enabled for Docker (country=$COUNTRY_CODE)."
  fi

  run_cmd 120 docker --version || return $?
  run_cmd 120 docker buildx version || return $?
  run_cmd 120 docker compose version || return $?
}

docker_ready() {
  command_exists docker || return 1
  docker buildx version >/dev/null 2>&1 || return 1
  docker compose version >/dev/null 2>&1 || return 1
}

docker_group_ready() {
  [[ "$TARGET_USER" == "root" ]] && return 0
  id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx docker
}

install_docker_engine() {
  apt_install ca-certificates curl gnupg python3 || return $?

  run_sudo 900 env DEBIAN_FRONTEND=noninteractive apt-get remove -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc || true

  run_sudo 60 install -m 0755 -d /etc/apt/keyrings || return $?

  if is_dry_run; then
    log_info "Would install Docker apt key and repository."
  else
    local tmp_key
    tmp_key="$(mktemp)"
    download_to https://download.docker.com/linux/ubuntu/gpg "$tmp_key" || {
      rm -f "$tmp_key"
      return 1
    }
    run_sudo 60 install -m 0644 "$tmp_key" /etc/apt/keyrings/docker.asc || {
      rm -f "$tmp_key"
      return 1
    }
    rm -f "$tmp_key"
  fi

  local arch codename
  arch="$(dpkg --print-architecture)"
  # shellcheck disable=SC1091
  codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")"
  [[ -n "$codename" ]] || return 1

  if [[ "$codename" != "noble" && "$codename" != "jammy" ]] && ! is_dry_run; then
    if ! curl -fsSI "https://download.docker.com/linux/ubuntu/dists/$codename/" >/dev/null 2>&1; then
      log_warn "Docker stable repository does not yet list Ubuntu $codename. Falling back to noble (24.04 LTS) repository."
      codename="noble"
    fi
  fi

  write_root_file 0644 /etc/apt/sources.list.d/docker.list \
    "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $codename stable
"
  APT_UPDATED=0
  apt_update || return $?
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || return $?
}

configure_docker_group() {
  run_sudo 120 groupadd -f docker || return $?
  if [[ "$TARGET_USER" != "root" ]]; then
    run_sudo 120 usermod -aG docker "$TARGET_USER"
  fi
}

configure_docker_daemon_mirrors() {
  local daemon_file="/etc/docker/daemon.json"
  local old tmp content

  run_sudo 60 install -d -m 0755 /etc/docker || return $?

  if is_dry_run; then
    log_info "Would merge Docker registry mirrors into $daemon_file"
    return 0
  fi

  old="$(mktemp)"
  tmp="$(mktemp)"
  if [[ -f "$daemon_file" ]]; then
    read_root_file "$daemon_file" >"$old"
    run_sudo 60 cp "$daemon_file" "$daemon_file.bak.$(date +%Y%m%d%H%M%S)" || true
  else
    printf "{}\n" >"$old"
  fi

  python3 - "$old" "$tmp" "${DOCKER_REGISTRY_MIRROR_URLS[@]}" <<'PY'
import json
import sys

old_path, out_path, *mirrors = sys.argv[1:]
try:
    with open(old_path, encoding="utf-8") as fh:
        data = json.load(fh)
except json.JSONDecodeError as exc:
    print(f"Invalid existing daemon.json: {exc}", file=sys.stderr)
    sys.exit(1)

existing = data.get("registry-mirrors", [])
if not isinstance(existing, list):
    print("Existing registry-mirrors is not a list; refusing to overwrite it.", file=sys.stderr)
    sys.exit(1)

merged = []
for mirror in list(existing) + mirrors:
    if mirror not in merged:
        merged.append(mirror)
data["registry-mirrors"] = merged

with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY
  local rc=$?
  if [[ "$rc" -ne 0 ]]; then
    rm -f "$old" "$tmp"
    return "$rc"
  fi

  content="$(<"$tmp")"
  write_root_file 0644 "$daemon_file" "$content"
  rc=$?
  rm -f "$old" "$tmp"
  return "$rc"
}

configure_buildkit_mirrors() {
  local config_file="/etc/docker/buildkitd.toml"
  local existing=""
  local block content tmp

  block="# ubuntu-bootstrap docker.io mirror
[registry.\"docker.io\"]
  mirrors = [\"${DOCKER_REGISTRY_MIRROR_HOSTS[0]}\", \"${DOCKER_REGISTRY_MIRROR_HOSTS[1]}\", \"${DOCKER_REGISTRY_MIRROR_HOSTS[2]}\"]
"

  if is_dry_run; then
    log_info "Would ensure BuildKit mirror config in $config_file"
    return 0
  fi

  if [[ -f "$config_file" ]]; then
    existing="$(read_root_file "$config_file")"
    run_sudo 60 cp "$config_file" "$config_file.bak.$(date +%Y%m%d%H%M%S)" || true
    tmp="$(mktemp)"
    printf "%s" "$existing" >"$tmp"
    python3 - "$tmp" "${DOCKER_REGISTRY_MIRROR_HOSTS[@]}" <<'PY'
import re
import sys

path, *mirrors = sys.argv[1:]
with open(path, encoding="utf-8") as fh:
    lines = fh.readlines()

header_re = re.compile(r'^\s*\[registry\."docker\.io"\]\s*$')
table_re = re.compile(r'^\s*\[')
start = next((i for i, line in enumerate(lines) if header_re.match(line)), None)

def mirror_line(indent="  "):
    values = ", ".join(f'"{mirror}"' for mirror in mirrors)
    return f"{indent}mirrors = [{values}]\n"

if start is None:
    if lines and lines[-1].strip():
        lines.append("\n")
    lines.extend([
        "# ubuntu-bootstrap docker.io mirror\n",
        '[registry."docker.io"]\n',
        mirror_line(),
    ])
else:
    end = len(lines)
    for index in range(start + 1, len(lines)):
        if table_re.match(lines[index]):
            end = index
            break

    block = lines[start:end]
    block_text = "".join(block)
    if not any(mirror in block_text for mirror in mirrors):
        for index in range(start + 1, end):
            if re.match(r'^\s*mirrors\s*=', lines[index]):
                if "[" not in lines[index] or "]" not in lines[index]:
                    print("Existing BuildKit docker.io mirrors entry is multi-line; refusing to edit automatically.", file=sys.stderr)
                    sys.exit(1)
                existing = re.findall(r'"([^"]+)"', lines[index])
                merged = []
                for item in existing + mirrors:
                    if item not in merged:
                        merged.append(item)
                indent = re.match(r'^(\s*)', lines[index]).group(1)
                lines[index] = mirror_line(indent).replace(
                    ", ".join(f'"{mirror}"' for mirror in mirrors),
                    ", ".join(f'"{mirror}"' for mirror in merged),
                )
                break
        else:
            lines.insert(start + 1, mirror_line())

with open(path, "w", encoding="utf-8") as fh:
    fh.writelines(lines)
PY
    local rc=$?
    if [[ "$rc" -ne 0 ]]; then
      rm -f "$tmp"
      return "$rc"
    fi
    content="$(<"$tmp")"
    rm -f "$tmp"
  else
    content="$block"
  fi

  write_root_file 0644 "$config_file" "$content"
}

restart_docker() {
  if has_systemd; then
    run_sudo 300 systemctl restart docker
  else
    run_sudo 300 service docker restart
  fi
}

configure_buildx_builder() {
  local script
  script="docker buildx rm ubuntu-bootstrap >/dev/null 2>&1 || true; docker buildx create --name ubuntu-bootstrap --driver docker-container --driver-opt network=host --buildkitd-config /etc/docker/buildkitd.toml --use; docker buildx inspect --bootstrap"
  if [[ "$TARGET_USER" != "root" ]] && id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
    run_user_cmd 300 sg docker -c "$script"
  else
    run_user_shell 300 "$script"
  fi
}

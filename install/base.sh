#!/usr/bin/env bash

install_base() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
      log_warn "This project targets Ubuntu 24.04/26.04; detected ID=${ID:-unknown}. Continuing best-effort."
    elif [[ "${VERSION_ID:-}" != "24.04" && "${VERSION_ID:-}" != "26.04" ]]; then
      log_warn "This project targets Ubuntu 24.04/26.04; detected VERSION_ID=${VERSION_ID:-unknown}. Continuing best-effort."
    fi
  fi

  configure_apt_mirror_if_needed || return $?

  apt_install \
    bash-completion \
    bat \
    build-essential \
    ca-certificates \
    curl \
    dnsutils \
    fd-find \
    fonts-noto-cjk \
    fonts-wqy-zenhei \
    git \
    gnupg \
    htop \
    iproute2 \
    iputils-ping \
    jq \
    language-pack-zh-hans \
    less \
    locales \
    lsb-release \
    make \
    net-tools \
    openssl \
    pkg-config \
    ripgrep \
    software-properties-common \
    tar \
    tmux \
    tree \
    unzip \
    vim \
    wget \
    xz-utils \
    zip || return $?

  redetect_country_if_unknown
  configure_apt_mirror_if_needed || return $?

  if command_exists locale-gen; then
    run_sudo 300 locale-gen en_US.UTF-8 zh_CN.UTF-8 || log_warn "locale-gen failed; continuing"
  fi
}

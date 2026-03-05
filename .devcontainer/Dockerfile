FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG TZ=Asia/Tokyo
ENV TZ="$TZ"
ARG USERNAME=dev
ARG DELTA_VERSION=0.18.2
ARG XH_VERSION=v0.25.3
ARG NVIM_VERSION=v0.11.6

# Create dev user
RUN useradd -m -s /bin/zsh -G sudo ${USERNAME} && \
  echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME}

# Minimal extra tools
RUN apt-get update && apt-get install -y --no-install-recommends \
  fzf man-db nano vim eza \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# git-delta
RUN set -eux && \
  ARCH=$(uname -m) && \
  if [ "$ARCH" = "x86_64" ]; then DELTA_ARCH="x86_64-unknown-linux-musl"; else DELTA_ARCH="aarch64-unknown-linux-gnu"; fi && \
  curl -fSL "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-$DELTA_ARCH.tar.gz" -o delta.tar.gz && \
  tar -xzf delta.tar.gz --strip-components=1 -C /usr/local/bin "delta-${DELTA_VERSION}-$DELTA_ARCH/delta" && \
  rm delta.tar.gz

# xh (HTTP client)
RUN set -eux && \
  ARCH=$(uname -m) && \
  if [ "$ARCH" = "x86_64" ]; then XH_ARCH="x86_64-unknown-linux-musl"; else XH_ARCH="aarch64-unknown-linux-musl"; fi && \
  curl -fSL "https://github.com/ducaale/xh/releases/download/${XH_VERSION}/xh-${XH_VERSION}-$XH_ARCH.tar.gz" -o xh.tar.gz && \
  tar -xzf xh.tar.gz --strip-components=1 -C /usr/local/bin "xh-${XH_VERSION}-$XH_ARCH/xh" && \
  rm xh.tar.gz

# Neovim
RUN set -eux && \
  ARCH=$(uname -m) && \
  if [ "$ARCH" = "x86_64" ]; then NVIM_ARCH="nvim-linux-x86_64"; else NVIM_ARCH="nvim-linux-arm64"; fi && \
  curl -fSL "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/$NVIM_ARCH.tar.gz" -o nvim.tar.gz && \
  tar -C /opt -xzf nvim.tar.gz && \
  ln -s "/opt/$NVIM_ARCH/bin/nvim" /usr/local/bin/nvim && \
  rm nvim.tar.gz

# Persist shell history
RUN mkdir /commandhistory \
  && touch /commandhistory/.zsh_history \
  && chown -R ${USERNAME} /commandhistory
RUN echo 'export HISTFILE=/commandhistory/.zsh_history' >> /home/${USERNAME}/.zshrc \
  && chown ${USERNAME}:${USERNAME} /home/${USERNAME}/.zshrc

# Workspace
RUN mkdir -p /workspace && chown ${USERNAME}:${USERNAME} /workspace

ENV DEVCONTAINER=true
ENV SHELL=/bin/zsh
ENV EDITOR=nano
ENV VISUAL=nano

# Firewall (optional: only functional when init-firewall.sh is present)
COPY init-firewall.sh firewall-status.sh /usr/local/bin/
COPY allowed-domains.conf /etc/allowed-domains.conf
RUN chmod +x /usr/local/bin/init-firewall.sh /usr/local/bin/firewall-status.sh && \
  echo "${USERNAME} ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/${USERNAME}-firewall && \
  chmod 0440 /etc/sudoers.d/${USERNAME}-firewall

USER ${USERNAME}
WORKDIR /workspace

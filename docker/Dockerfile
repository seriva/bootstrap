# ==============================================================================
# bootstrap Agent Container
# A turnkey agentic development runtime pairing T3 Code (orchestrator)
# with code-server (VS Code web) and configurable coding harnesses.
# ==============================================================================

# Pinned for reproducible builds; bump deliberately to pick up a newer code-server
ARG CODE_SERVER_VERSION=4.144.0
FROM codercom/code-server:${CODE_SERVER_VERSION}

USER root

# Node.js major version from NodeSource (override with the NODE_MAJOR build arg)
ARG NODE_MAJOR=24

# Install development essentials, Node.js, and GitHub CLI
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    build-essential \
    python3 \
    python3-pip \
    ca-certificates \
    ripgrep \
    jq \
    dumb-init \
    sudo \
    && mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs gh \
    && rm -rf /var/lib/apt/lists/*

# Install T3 Code CLI & web server system-wide
RUN T3CODE_HOME=/opt/t3 T3CODE_INSTALL_BIN_DIR=/usr/local/bin sh -c 'curl -fsSL https://t3.codes/install.sh | sh' \
    && chmod -R 755 /opt/t3

# Configure passwordless sudo for 'coder' user
RUN echo "coder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coder-nopasswd \
    && chmod 0440 /etc/sudoers.d/coder-nopasswd

# Setup environment paths
ENV NPM_CONFIG_PREFIX="/home/coder/.npm-global"
ENV T3CODE_HOME="/home/coder/.t3"
# Antigravity's installer puts agy in ~/.antigravity/bin
ENV PATH="/home/coder/.npm-global/bin:/home/coder/.local/bin:/home/coder/.antigravity/bin:${PATH}"

RUN echo "export PATH=\"$PATH\" NPM_CONFIG_PREFIX=\"$NPM_CONFIG_PREFIX\" T3CODE_HOME=\"$T3CODE_HOME\"" > /etc/profile.d/agent-path.sh

# Copy container helper scripts
COPY --chmod=755 docker/harness-install /usr/local/bin/harness-install
COPY --chmod=755 docker/t3-pair /usr/local/bin/t3-pair
COPY --chmod=755 docker/upgrade.sh /usr/local/bin/agent-upgrade
COPY --chmod=755 docker/entrypoint.sh /home/coder/entrypoint.sh

# Copy bootstrap skills & installer so they are pre-baked into the image
RUN mkdir -p /opt/bootstrap
COPY skills /opt/bootstrap/skills
COPY --chmod=755 install.sh /opt/bootstrap/install.sh
RUN chown -R coder:coder /opt/bootstrap

# Switch to non-root 'coder' user
USER coder
WORKDIR /home/coder

# Pre-create standard config and cache directories
RUN mkdir -p /home/coder/.npm-global \
    /home/coder/.local/bin \
    /home/coder/.t3 \
    /home/coder/.claude \
    /home/coder/.gemini \
    /home/coder/.codex \
    /home/coder/.config/opencode \
    /home/coder/.pi/agent \
    /home/coder/.ssh \
    /home/coder/workspace

# Build-time worker harnesses to pre-install (comma-separated: claude,codex,opencode,pi,agy).
# harness-install links the bootstrap skills itself; with no workers, link them directly.
ARG ENABLED_WORKERS="claude,codex,opencode"
RUN if [ -n "${ENABLED_WORKERS}" ]; then \
      /usr/local/bin/harness-install "${ENABLED_WORKERS}"; \
    else \
      /opt/bootstrap/install.sh; \
    fi

WORKDIR /home/coder/workspace

# 8080: code-server (VS Code web)
# 8011: T3 Code (Orchestrator web server)
EXPOSE 8080 8011

ENTRYPOINT ["/usr/bin/dumb-init", "/home/coder/entrypoint.sh"]
CMD []


FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# === Pinned versions (update these to stay aligned with host) ===
ARG PYTHON_VERSION=3.12.12
ARG NODE_MAJOR=25
ARG GITLEAKS_VERSION=8.30.0
ARG RUST_VERSION=1.93.0
ARG UV_VERSION=0.10.3
ARG GH_VERSION=2.86.0
ARG GO_VERSION=1.25.7

# ============================================================
# Layer 1: System deps + Playwright system libs + vim (~350MB)
# Rarely changes. Includes pyenv build deps and Chromium runtime deps.
# ============================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # pyenv Python build dependencies
    build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
    libsqlite3-dev libncursesw5-dev xz-utils tk-dev libxml2-dev \
    libxmlsec1-dev libffi-dev liblzma-dev \
    # Utilities
    curl wget jq shellcheck tmux util-linux gosu vim \
    # Playwright Chromium system dependencies (Ubuntu 24.04)
    libasound2t64 libatk-bridge2.0-0t64 libatk1.0-0t64 \
    libatspi2.0-0t64 libcairo2 libcups2t64 libdbus-1-3 \
    libdrm2 libgbm1 libglib2.0-0t64 libnspr4 libnss3 \
    libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 \
    libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 \
    fonts-noto-color-emoji fonts-liberation \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# Layer 2: gcloud CLI (~1.08GB, almost never changes)
# ============================================================
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
      | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
      > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && apt-get update && apt-get install -y google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# Layer 3: Go (~243MB, rarely changes)
# ============================================================
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" \
      | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:${PATH}"

# ============================================================
# Layer 4: Node.js + Claude Code + pm2 (~330MB)
# ============================================================
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*
RUN npm install -g @anthropic-ai/claude-code pm2

# ============================================================
# Layer 5: Binary tools — gh, gitleaks, uv (~117MB)
# ============================================================
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${ARCH}.deb" \
      -o /tmp/gh.deb && dpkg -i /tmp/gh.deb && rm /tmp/gh.deb

RUN ARCH=$(dpkg --print-architecture) \
    && GL_ARCH=$([ "$ARCH" = "amd64" ] && echo "x64" || echo "arm64") \
    && curl -sL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GL_ARCH}.tar.gz" \
      | tar xz -C /usr/local/bin gitleaks && chmod +x /usr/local/bin/gitleaks

RUN curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" \
      | env UV_INSTALL_DIR=/usr/local/bin sh

# ============================================================
# Layer 6: Workspace directory + entrypoint (tiny)
# ============================================================
RUN mkdir -p /workspace && chown vscode:vscode /workspace
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ============================================================
# Layer 7: Rust toolchain (~800MB, rarely changes)
# Installed system-wide (root) to avoid UID-remapping chown issues
# ============================================================
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo
ENV PATH="/usr/local/cargo/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --default-toolchain ${RUST_VERSION} --no-modify-path \
    && chmod -R a+rX /usr/local/rustup /usr/local/cargo

# ============================================================
# Layer 8: pyenv + Python (~329MB, changes on version bump only)
# Installed to /opt/pyenv (system-wide) to avoid UID-remapping chown delay
# ============================================================
ENV PYENV_ROOT=/opt/pyenv
ENV PATH="${PYENV_ROOT}/shims:${PYENV_ROOT}/bin:${PATH}"
RUN curl -sS https://pyenv.run | bash \
    && pyenv install ${PYTHON_VERSION} \
    && pyenv global ${PYTHON_VERSION} \
    && chmod -R a+rX /opt/pyenv

# ============================================================
# Layer 9: Python core packages (~500MB, most frequently updated)
# All system-wide installs as root (pyenv in /opt is root-owned)
# ============================================================
COPY requirements-base.txt /tmp/requirements-base.txt
RUN pip install --no-cache-dir -r /tmp/requirements-base.txt

# ============================================================
# Layer 10: Playwright Chromium browser (~622MB)
# Install as vscode so browsers go to vscode's cache dir
# ============================================================
USER vscode
ENV PLAYWRIGHT_BROWSERS_PATH=/home/vscode/.cache/ms-playwright
RUN playwright install chromium

# ============================================================
# Layer 11: pre-commit framework (~15MB)
# ============================================================
USER root
RUN pip install --no-cache-dir pre-commit \
    && chmod -R a+rX /opt/pyenv

# ============================================================
# Final: PATH + workspace setup
# ============================================================
ENV PATH="/workspace/.venv/bin:${PATH}"
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

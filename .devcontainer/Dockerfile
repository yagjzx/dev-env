FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# === Pinned versions (update these to stay aligned with host) ===
ARG PYTHON_VERSION=3.12.12
ARG NODE_MAJOR=22
ARG GITLEAKS_VERSION=8.30.0
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
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
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
RUN curl -fsSL "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.deb" \
      -o /tmp/gh.deb && dpkg -i /tmp/gh.deb && rm /tmp/gh.deb

RUN curl -sL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
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
# Layer 7: pyenv + Python (~329MB, changes on version bump only)
# Switch to vscode user for all remaining operations
# ============================================================
USER vscode
RUN curl -sS https://pyenv.run | bash
ENV PYENV_ROOT="/home/vscode/.pyenv"
ENV PATH="${PYENV_ROOT}/shims:${PYENV_ROOT}/bin:${PATH}"
RUN pyenv install ${PYTHON_VERSION} && pyenv global ${PYTHON_VERSION}

# ============================================================
# Layer 8: Python core packages (~500MB, most frequently updated)
# COPY requirements-base.txt first for cache-friendly rebuilds
# ============================================================
COPY requirements-base.txt /tmp/requirements-base.txt
RUN pip install --no-cache-dir -r /tmp/requirements-base.txt

# ============================================================
# Layer 9: Playwright Chromium browser (~622MB)
# Must come after pip install playwright. Only chromium to save space.
# ============================================================
RUN playwright install chromium

# ============================================================
# Layer 10: pre-commit framework (~15MB)
# ============================================================
RUN pip install --no-cache-dir pre-commit

# ============================================================
# Final: PATH + workspace setup
# ============================================================
ENV PATH="/workspace/.venv/bin:${PATH}"
WORKDIR /workspace

# Run entrypoint as root (it will drop to vscode after UID fix)
USER root
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

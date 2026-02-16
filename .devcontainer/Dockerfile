FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# === Pinned versions (update these to stay aligned) ===
ARG PYTHON_VERSION=3.12.12
ARG NODE_MAJOR=22
ARG GITLEAKS_VERSION=8.30.0
ARG UV_VERSION=0.10.3
ARG GH_VERSION=2.86.0

# === System deps for pyenv Python build + utilities ===
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
    libsqlite3-dev libncursesw5-dev xz-utils tk-dev libxml2-dev \
    libxmlsec1-dev libffi-dev liblzma-dev \
    curl wget jq shellcheck tmux util-linux gosu \
    && rm -rf /var/lib/apt/lists/*

# === Node.js ===
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# === Claude Code ===
RUN npm install -g @anthropic-ai/claude-code

# === gh CLI ===
RUN curl -fsSL https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.deb -o /tmp/gh.deb \
    && dpkg -i /tmp/gh.deb && rm /tmp/gh.deb

# === gitleaks ===
RUN curl -sL https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz \
    | tar xz -C /usr/local/bin gitleaks \
    && chmod +x /usr/local/bin/gitleaks

# === uv ===
RUN curl -LsSf https://astral.sh/uv/${UV_VERSION}/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# === gcloud CLI ===
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list \
    && apt-get update && apt-get install -y google-cloud-cli \
    && rm -rf /var/lib/apt/lists/*

# === Create workspace directory (as root, before user switch) ===
RUN mkdir -p /workspace && chown vscode:vscode /workspace

# === Entrypoint (UID remapping at runtime) ===
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# === Switch to non-root user for pyenv/pip installs ===
USER vscode

# === pyenv + Python (as vscode user) ===
RUN curl -sS https://pyenv.run | bash
ENV PYENV_ROOT="/home/vscode/.pyenv"
ENV PATH="${PYENV_ROOT}/shims:${PYENV_ROOT}/bin:${PATH}"
RUN pyenv install ${PYTHON_VERSION} && pyenv global ${PYTHON_VERSION}

# === pre-commit framework ===
RUN pip install --no-cache-dir pre-commit

# === Workspace setup ===
ENV PATH="/workspace/.venv/bin:${PATH}"
WORKDIR /workspace

# Run entrypoint as root (it will drop to vscode after UID fix)
USER root
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

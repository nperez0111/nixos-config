FROM ghcr.io/getpaseo/paseo:latest

# Install tools as root, then grant paseo passwordless sudo so agents can
# escalate when needed (e.g. apt install) without running the daemon as root.
USER root

# System packages: dev tools + GitHub CLI from its official apt repo.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl gpg unzip ripgrep fd-find python3 sudo micro \
 && ln -s "$(command -v fdfind)" /usr/local/bin/fd \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# Grant paseo user passwordless sudo.
RUN echo "paseo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/paseo \
 && chmod 0440 /etc/sudoers.d/paseo

# Coding agent CLIs + dev tooling.
RUN npm install -g @anthropic-ai/claude-code opencode-ai vite-plus
ENV BUN_INSTALL=/usr/local
RUN curl -fsSL https://bun.sh/install | bash
ENV UV_INSTALL_DIR=/usr/local/bin
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Fix ownership of anything npm/bun/uv created under /home/paseo during build.
RUN chown -R 1000:1000 /home/paseo

# Tell git to trust all directories (the bind-mounted /workspace comes from
# macOS with different uid mapping; without this, git refuses to operate).
RUN git config --system --add safe.directory '*'

# Use the original entrypoint — it sets up env vars, creates dirs, and drops
# to the paseo user via gosu. No ENTRYPOINT/CMD override needed.

FROM ghcr.io/getpaseo/paseo:latest

# Install tools as root, then grant paseo passwordless sudo so agents can
# escalate when needed (e.g. apt install) without running the daemon as root.
USER root

# System packages: dev tools + GitHub CLI + Docker CLI from official apt repos.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl gpg unzip ripgrep fd-find python3 sudo micro ca-certificates \
      jq rsync \
 && ln -s "$(command -v fdfind)" /usr/local/bin/fd \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && curl -fsSL https://download.docker.com/linux/debian/gpg \
      | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh docker-ce-cli docker-compose-plugin \
 && rm -rf /var/lib/apt/lists/*

# Create a docker group matching the host socket GID (root/0 on OrbStack)
# and add paseo to it so docker commands work without sudo.
RUN groupadd -g 998 docker || true \
 && usermod -aG docker,root paseo

# Grant paseo user passwordless sudo.
RUN echo "paseo ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/paseo \
 && chmod 0440 /etc/sudoers.d/paseo

# Coding agent CLIs + dev tooling.
RUN npm install -g @anthropic-ai/claude-code @openai/codex opencode-ai vite-plus
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

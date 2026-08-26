FROM ghcr.io/getpaseo/paseo:latest

# Run everything as root. The base image's entrypoint drops to uid 1000 via
# gosu, which causes endless permission problems with tools that write to
# /home/paseo (npm cache, opencode XDG dirs, bun cache, etc.). Overriding
# the entrypoint to run the node server directly as root sidesteps all of it.
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

# Coding agent CLIs + dev tooling.
RUN npm install -g @anthropic-ai/claude-code opencode-ai vite-plus
ENV BUN_INSTALL=/usr/local
RUN curl -fsSL https://bun.sh/install | bash
ENV UV_INSTALL_DIR=/usr/local/bin
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Replicate the env vars from the base entrypoint so the server and agents
# find their config/cache/state directories in the right places.
ENV HOME=/home/paseo \
    PASEO_HOME=/home/paseo/.paseo \
    PASEO_LISTEN=0.0.0.0:6767 \
    PASEO_WEB_UI_ENABLED=true \
    PASEO_LOG_LEVEL=info \
    PASEO_LOG_FORMAT=json \
    CLAUDE_CONFIG_DIR=/home/paseo/.claude \
    CODEX_HOME=/home/paseo/.codex \
    XDG_CONFIG_HOME=/home/paseo/.config \
    XDG_DATA_HOME=/home/paseo/.local/share \
    XDG_STATE_HOME=/home/paseo/.local/state \
    XDG_CACHE_HOME=/home/paseo/.cache

# Create all the directories the entrypoint would have created.
RUN mkdir -p /home/paseo/.paseo /home/paseo/.claude /home/paseo/.codex \
             /home/paseo/.config /home/paseo/.local/share \
             /home/paseo/.local/state /home/paseo/.cache

# Override the entrypoint to skip gosu; run the server directly as root.
# /etc/paseo-server-entry is a text file containing the real JS entry path,
# not a JS file itself. The original entrypoint does `entry="$(cat ...)"`.
ENTRYPOINT []
CMD ["sh", "-c", "exec node \"$(cat /etc/paseo-server-entry)\""]

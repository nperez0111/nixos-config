FROM ghcr.io/getpaseo/paseo:latest

# Install coding agent CLIs globally. The entrypoint drops to the `paseo` user
# via gosu, so leaving USER as root here is correct — it mirrors the base
# image's expectation.
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl gpg unzip ripgrep fd-find \
 && ln -s "$(command -v fdfind)" /usr/local/bin/fd \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | gpg --dearmor -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*
RUN npm install -g @anthropic-ai/claude-code opencode-ai vite-plus
ENV BUN_INSTALL=/usr/local
RUN curl -fsSL https://bun.sh/install | bash
ENV UV_INSTALL_DIR=/usr/local/bin
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# npm install -g can create directories under /home/paseo owned by root (e.g.
# .local/share/opencode/). The entrypoint drops to uid 1000, so fix ownership
# now to avoid PermissionDenied errors at runtime.
RUN chown -R 1000:1000 /home/paseo

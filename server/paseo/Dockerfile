FROM ghcr.io/getpaseo/paseo:latest

# Install coding agent CLIs globally. The entrypoint drops to the `paseo` user
# via gosu, so leaving USER as root here is correct — it mirrors the base
# image's expectation.
USER root
RUN npm install -g @anthropic-ai/claude-code opencode-ai

# npm install -g can create directories under /home/paseo owned by root (e.g.
# .local/share/opencode/). The entrypoint drops to uid 1000, so fix ownership
# now to avoid PermissionDenied errors at runtime.
RUN chown -R 1000:1000 /home/paseo

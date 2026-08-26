FROM ghcr.io/getpaseo/paseo:latest

# Install coding agent CLIs globally. The entrypoint drops to the `paseo` user
# via gosu, so leaving USER as root here is correct — it mirrors the base
# image's expectation.
USER root
RUN npm install -g @anthropic-ai/claude-code opencode-ai

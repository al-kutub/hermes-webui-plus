# hermes-webui-plus
#
# nesquena/hermes-webui + hermes-agent + Slack gateway + the full Claude Code CLI
# stack (claude CLI, claude-code-acp ACP bridge, rtk token-saving integration),
# so a single Railway service gives: the Hermes web UI, a Slack bot, AND Hermes
# driving the real Claude Code CLI (via ACP) on your Claude Max subscription with
# rtk active - not the Anthropic API.
FROM ghcr.io/nesquena/hermes-webui:latest

USER root

# 1) Patch the base launch (/hermeswebui_init.bash) to also start the hermes
#    gateway alongside the web UI when a Slack token is present.
RUN chmod u+w /hermeswebui_init.bash \
 && sed -i 's#^cd /app; python server.py#cd /app; if [ -n "${SLACK_BOT_TOKEN:-}" ] || [ "${HERMES_GATEWAY_ENABLED:-}" = "1" ]; then echo "[hermes-webui-plus] starting hermes gateway"; (python -c "from hermes_cli.gateway import run_gateway; run_gateway()" >/tmp/hermes-gateway.log 2>\&1 \&); fi; python server.py#' /hermeswebui_init.bash \
 && chmod 555 /hermeswebui_init.bash \
 && grep -q run_gateway /hermeswebui_init.bash

# 2) Build tools (some agent deps compile on the slim base) + Node.js 22 (the
#    claude CLI + claude-code-acp are npm packages; the base image is Python-only).
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential rsync ca-certificates curl gnupg \
 && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/* && apt-get clean \
 && node --version && npm --version

# 3) Claude Code CLI + the ACP bridge that lets Hermes drive it as a subprocess.
RUN npm install -g @anthropic-ai/claude-code @zed-industries/claude-code-acp \
 && command -v claude && command -v claude-code-acp

# 4) rtk token-saving stack (mirrors al-kutub/paperclip-plus): rtk, ygrep, static
#    jq. x86_64 assets (Railway = amd64).
RUN set -e; \
    curl -fsSL https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64 -o /usr/local/bin/jq && chmod 0755 /usr/local/bin/jq; \
    rtk_url="$(curl -fsSL https://api.github.com/repos/rtk-ai/rtk/releases/latest | grep -oE 'https://[^"]*rtk-x86_64-unknown-linux-musl\.tar\.gz' | head -1)"; \
    [ -n "$rtk_url" ] || rtk_url="https://github.com/rtk-ai/rtk/releases/download/v0.42.2/rtk-x86_64-unknown-linux-musl.tar.gz"; \
    curl -fsSL "$rtk_url" | tar -xz -C /tmp && install -m0755 "$(find /tmp -type f -name rtk | head -1)" /usr/local/bin/rtk; \
    yg_url="$(curl -fsSL https://api.github.com/repos/yetidevworks/ygrep/releases/latest | grep -oE 'https://[^"]*ygrep-[0-9.]+-linux-x86_64\.tar\.gz' | head -1)"; \
    [ -n "$yg_url" ] || yg_url="https://github.com/yetidevworks/ygrep/releases/download/v3.2.4/ygrep-3.2.4-linux-x86_64.tar.gz"; \
    curl -fsSL "$yg_url" | tar -xz -C /tmp && install -m0755 "$(find /tmp -type f -name ygrep | head -1)" /usr/local/bin/ygrep; \
    rm -rf /tmp/rtk* /tmp/ygrep*; \
    rtk --version; ygrep --version

# 5) Stage the rtk Claude Code config (settings.json PreToolUse hook -> `rtk hook
#    claude`, RTK.md, CLAUDE.md @RTK.md). Same as paperclip-plus.
COPY claude/agent-config/ /opt/rtk-claude-config/
RUN mkdir -p /etc/claude-code \
 && cp /opt/rtk-claude-config/settings.json /etc/claude-code/managed-settings.json \
 && chmod -R a+rX /etc/claude-code /opt/rtk-claude-config

ENV PATH="/usr/local/bin:${PATH}"

# 6) Seed rtk config + dirs into the hermeswebui user's home so the claude CLI
#    (driven by claude-code-acp) loads the rtk hook + rtk can write its DB. The
#    container runs as hermeswebui (HOME=/home/hermeswebui); no volume on it, so
#    baking at build is durable.
USER hermeswebui
RUN mkdir -p /home/hermeswebui/.claude /home/hermeswebui/.local/share/rtk /home/hermeswebui/.config /home/hermeswebui/.cache \
 && cp /opt/rtk-claude-config/settings.json /opt/rtk-claude-config/RTK.md /opt/rtk-claude-config/CLAUDE.md /home/hermeswebui/.claude/ \
 && (yes | HOME=/home/hermeswebui /usr/local/bin/rtk init -g >/dev/null 2>&1 || true) \
 && HOME=/home/hermeswebui rtk --version

# 7) Pre-build the runtime venv with hermes-agent[all] so first boot is fast and
#    the webui/gateway have the agent.
RUN cp -a /apptoo/requirements.txt /app/requirements.txt \
 && export UV_PROJECT_ENVIRONMENT=/app/venv VIRTUAL_ENV=/app/venv \
 && uv venv /app/venv \
 && . /app/venv/bin/activate \
 && uv pip install -U pip setuptools --trusted-host pypi.org --trusted-host files.pythonhosted.org \
 && uv pip install -r /app/requirements.txt --trusted-host pypi.org --trusted-host files.pythonhosted.org \
 && uv pip install "hermes-agent[all]" --trusted-host pypi.org --trusted-host files.pythonhosted.org \
 && python -c "import hermes_cli, hermes_cli.gateway; print('hermes_cli OK')" \
 && touch /app/venv/.deps_installed \
 && HOME=/home/hermeswebui /app/venv/bin/hermes config set provider copilot-acp \
 && HOME=/home/hermeswebui /app/venv/bin/hermes config set model copilot-acp

USER root
CMD ["/hermeswebui_init.bash"]

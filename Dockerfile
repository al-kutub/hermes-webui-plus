# hermes-webui-plus
#
# nesquena/hermes-webui (the Hermes Agent web UI) PLUS hermes-agent itself PLUS
# the hermes-agent messaging gateway (Slack / Discord / Telegram via Socket Mode),
# so a single Railway service gives the web UI and a Slack bot.
#
# Why we install hermes-agent here: the published single-container webui image
# does NOT bundle hermes-agent (its runtime install is skipped because no agent
# source is staged), so the webui boots with "agent dir: NOT FOUND" and agent
# features (model calls, Slack) don't work. We bake the agent into the runtime
# venv (/app/venv) at BUILD time and touch the .deps_installed marker so the base
# init script skips its install and boots fast with the agent present.
#
# We also patch the base launch to background the hermes gateway alongside the
# web UI when a Slack token is present (or HERMES_GATEWAY_ENABLED=1). Slack uses
# Socket Mode (outbound), so it needs no extra port and coexists on :8787.
FROM ghcr.io/nesquena/hermes-webui:latest

USER root

# 1) Patch the base launch (/hermeswebui_init.bash) to also start the gateway.
RUN chmod u+w /hermeswebui_init.bash \
 && sed -i 's#^cd /app; python server.py#cd /app; if [ -n "${SLACK_BOT_TOKEN:-}" ] || [ "${HERMES_GATEWAY_ENABLED:-}" = "1" ]; then echo "[hermes-webui-plus] starting hermes gateway"; (python -c "from hermes_cli.gateway import run_gateway; run_gateway()" >/tmp/hermes-gateway.log 2>\&1 \&); fi; python server.py#' /hermeswebui_init.bash \
 && chmod 555 /hermeswebui_init.bash \
 && grep -q run_gateway /hermeswebui_init.bash

# 2) Build tools for any agent deps that need compiling on the slim base.
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential rsync \
 && rm -rf /var/lib/apt/lists/* && apt-get clean

# 3) Pre-build the runtime venv (/app/venv) as the hermeswebui user with the
#    webui requirements + hermes-agent[all], then mark deps installed so the base
#    init script's runtime install is skipped (fast boot, agent present).
USER hermeswebui
RUN cp -a /apptoo/requirements.txt /app/requirements.txt \
 && export UV_PROJECT_ENVIRONMENT=/app/venv VIRTUAL_ENV=/app/venv \
 && uv venv /app/venv \
 && . /app/venv/bin/activate \
 && uv pip install -U pip setuptools --trusted-host pypi.org --trusted-host files.pythonhosted.org \
 && uv pip install -r /app/requirements.txt --trusted-host pypi.org --trusted-host files.pythonhosted.org \
 && uv pip install "hermes-agent[all]" --trusted-host pypi.org --trusted-host files.pythonhosted.org \
 && python -c "import hermes_cli, hermes_cli.gateway; print('hermes_cli OK')" \
 && touch /app/venv/.deps_installed

USER root
CMD ["/hermeswebui_init.bash"]

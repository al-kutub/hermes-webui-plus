# hermes-webui-plus
#
# nesquena/hermes-webui (the Hermes Agent web UI) PLUS the hermes-agent messaging
# gateway (Slack / Discord / Telegram via Socket Mode) running in the SAME
# container, so a single Railway service gives both the web UI and a Slack bot.
#
# The base image's CMD (/hermeswebui_init.bash) sets up /app/venv at runtime
# (installing hermes-agent[all]), drops to the unprivileged `hermeswebui` user,
# then runs `cd /app; python server.py` (the web UI on :8787). We patch that
# final launch line to ALSO background the hermes gateway in the same activated
# venv + environment, when a Slack bot token is present (or HERMES_GATEWAY_ENABLED=1).
# The gateway uses Slack Socket Mode (outbound only), so it needs no extra port
# and coexists with the web UI. Gateway command matches hermes-station's:
#   python -c "from hermes_cli.gateway import run_gateway; run_gateway()"
FROM ghcr.io/nesquena/hermes-webui:latest

USER root

RUN chmod u+w /hermeswebui_init.bash \
 && sed -i 's#^cd /app; python server.py#cd /app; if [ -n "${SLACK_BOT_TOKEN:-}" ] || [ "${HERMES_GATEWAY_ENABLED:-}" = "1" ]; then echo "[hermes-webui-plus] starting hermes gateway"; (python -c "from hermes_cli.gateway import run_gateway; run_gateway()" >/tmp/hermes-gateway.log 2>\&1 \&); fi; python server.py#' /hermeswebui_init.bash \
 && chmod 555 /hermeswebui_init.bash \
 && grep -q run_gateway /hermeswebui_init.bash

USER root
CMD ["/hermeswebui_init.bash"]

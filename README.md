# hermes-webui-plus

[nesquena/hermes-webui](https://github.com/nesquena/hermes-webui) (the Hermes
Agent web UI) **plus the hermes-agent messaging gateway** (Slack / Discord /
Telegram via Socket Mode) in one container, so a single Railway service gives
you both the web UI and a Slack bot.

## How it works

The base image runs the web UI on `:8787` and the agent in-process. This image
adds a one-line patch to the base launch script so it ALSO backgrounds the
hermes gateway (`python -c "from hermes_cli.gateway import run_gateway; run_gateway()"`)
in the same venv + environment, when `SLACK_BOT_TOKEN` is set (or
`HERMES_GATEWAY_ENABLED=1`). Slack uses Socket Mode, so the gateway needs no
inbound port and coexists with the web UI.

## Deploy on Railway

1. Create a service with source image `ghcr.io/al-kutub/hermes-webui-plus:latest`
   (built + pushed by `.github/workflows/publish.yml`).
2. Set the env vars from [`.env.example`](.env.example): `HERMES_WEBUI_PASSWORD`,
   `OPENROUTER_API_KEY`, and the Slack tokens (`SLACK_BOT_TOKEN`,
   `SLACK_APP_TOKEN`, `SLACK_ALLOWED_USERS`). Set `HERMES_WEBUI_HOST=0.0.0.0`.
3. Attach a volume for persistence: `railway volume add -m /home/hermeswebui/.hermes`.
4. Generate a domain pointed at port `8787`.

## Verify

- Web UI: open the domain (password gate).
- Slack: gateway logs at `/tmp/hermes-gateway.log` in the container; the bot
  connects via Socket Mode and responds to allowed users.

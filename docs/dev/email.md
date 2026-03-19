# Email Development with Mailpit

## Overview

All emails sent in dev are captured by Mailpit — never delivered externally.

- **Mailpit UI:** http://localhost:8025
- **SMTP:** host `localhost`, port `1025`, no auth

## Configuration

Dev Swoosh config (already in `config/dev.exs`):

```elixir
config :kith, Kith.Mailer,
  adapter: Swoosh.Adapters.SMTP,
  relay: "localhost",
  port: 1025,
  ssl: false,
  tls: :never,
  auth: :never
```

## Clearing the Inbox

Open the Mailpit UI and click the trash icon, or:

```bash
curl -X DELETE http://localhost:8025/api/v1/messages
```

## Production Adapters

Set `MAILER_ADAPTER` env var: `smtp` (default), `mailgun`, `ses`, or `postmark`.
See `config/runtime.exs` for required env vars per adapter.

# Open Cookbook

A private recipe catalog and meal planner built with Elixir and Phoenix LiveView. Chat with Claude, save recipes through an authenticated Speakeasy MCP connection, and use the app to plan, shop, and cook.

## Features

- **Authenticated API** — Save, search, read, update, and delete recipes; organize weekly meal slots; and read shopping lists. An OpenAPI description supports hosting these operations as MCP tools in Speakeasy.
- **Recipe Management** — Full CRUD for recipes with ingredients, steps, tags, and metadata.
- **Cook Mode** — Step-by-step guided cooking view.
- **Meal Planner** — Weekly lunch and dinner slots, editable from the dashboard or API.
- **Shopping Lists** — Auto-generated from your weekly meal plan with ingredient aggregation.
- **Unit System Preference** — Metric and imperial ingredient options, available to Claude through the profile API.
- **Serving Adjustment** — Scale numeric ingredient quantities locally. Non-numeric quantities stay unchanged.
- **Private Authentication** — Email magic links restricted to one allowed email, 30-day browser sessions, and revocable 90-day API tokens.

There is no embedded AI service or OpenRouter dependency. Existing recipe sources and generated recipes remain stored.

## Tech Stack

- [Elixir](https://elixir-lang.org/) ~> 1.15
- [Phoenix](https://www.phoenixframework.org/) ~> 1.8 with LiveView ~> 1.1
- PostgreSQL
- [Tailwind CSS](https://tailwindcss.com/) + [DaisyUI](https://daisyui.com/)
- [Swoosh](https://github.com/swoosh/swoosh) + [Resend](https://resend.com/) for email
- Deployable on [Fly.io](https://fly.io/)

## Getting Started

### Prerequisites

- Elixir ~> 1.15 / OTP
- PostgreSQL (default port `5434` in dev)
- Node.js (for asset tooling)

### Setup

```bash
# Install dependencies and set up the database
mix setup

# Start the dev server
mix phx.server
```

The app will be available at [http://localhost:4000](http://localhost:4000).

### Environment Variables

| Variable | Description |
|---|---|
| `ALLOWED_EMAIL` | The single email address allowed to log in |
| `RESEND_API_KEY` | API key for sending magic link emails (Resend) |
| `MAIL_FROM` | Authorized sender address for magic-link emails |
| `DATABASE_URL` | PostgreSQL connection string (prod only) |
| `SECRET_KEY_BASE` | Phoenix secret key (prod only) |
| `PHX_HOST` | Public hostname (prod only) |

### Running Tests

```bash
mix test
```

Tests expect PostgreSQL on port `5434`. Before finishing a change, run `mix precommit`.

## Connect Claude through Speakeasy

Follow [Set up the private Speakeasy connection](docs/speakeasy-setup.md). Local code and tests do not create or deploy the MCP server.

The API contract is available at `/api/openapi.json`. To export an uploadable copy, run:

```bash
mix cookbook.openapi --server https://open-cookbook.fly.dev
```

This writes `priv/openapi.json`. Edit `lib/cookbook_web/open_api.ex`, not the exported file, when changing the contract.

API requests require `Authorization: Bearer` with a token created in **Connections** at `/settings/connections`. Browser cookies do not authorize API requests. Never put a token in a prompt, URL, tool argument, or committed file.

Recipe creation requires an `Idempotency-Key` header. Reuse it only when retrying the same request within 24 hours. Recipe updates replace any explicitly supplied ingredient or step array; omitted arrays remain unchanged. Meal-slot updates replace that slot only, and an empty recipe list clears it.

## License

Private project.

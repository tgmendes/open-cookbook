# Open Cookbook

A personal recipe manager and meal planner built with Elixir, Phoenix LiveView, and AI-powered recipe generation.

## Features

- **AI Recipe Creation** — Describe what you want to cook, paste a URL, or upload a photo. The app uses AI to generate, scrape, or extract recipes automatically.
- **Recipe Management** — Full CRUD for recipes with ingredients, steps, tags, and metadata.
- **Cook Mode** — Step-by-step guided cooking view.
- **Meal Planner** — Weekly meal planning with drag-and-drop. AI-suggested plans based on your recipe library.
- **Shopping Lists** — Auto-generated from your weekly meal plan with ingredient aggregation.
- **Unit System Preference** — Toggle between metric and imperial units. Persists per-user and filters both the ingredient dropdown and AI-generated recipes.
- **Magic Link Auth** — Passwordless login via email, restricted to a single allowed email.

## Tech Stack

- [Elixir](https://elixir-lang.org/) ~> 1.15
- [Phoenix](https://www.phoenixframework.org/) ~> 1.8 with LiveView ~> 1.1
- PostgreSQL
- [Tailwind CSS](https://tailwindcss.com/) + [DaisyUI](https://daisyui.com/)
- [OpenRouter](https://openrouter.ai/) API for AI features
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
| `OPENROUTER_API_KEY` | API key for AI recipe features (OpenRouter) |
| `RESEND_API_KEY` | API key for sending magic link emails (Resend) |
| `DATABASE_URL` | PostgreSQL connection string (prod only) |
| `SECRET_KEY_BASE` | Phoenix secret key (prod only) |
| `PHX_HOST` | Public hostname (prod only) |

### Running Tests

```bash
mix test
```

## License

Private project.

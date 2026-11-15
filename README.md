# Open Cookbook

A private recipe catalog and meal planner built with Elixir and Phoenix LiveView. Chat with Claude, save recipes through an authenticated Speakeasy MCP connection, and use the app to plan, shop, and cook.

## Features

- **Authenticated API** — Save, search, read, update, and delete recipes; organize weekly meal slots; and read shopping lists. An OpenAPI description supports hosting these operations as MCP tools in Speakeasy.
- **Recipe Management** — Full CRUD for recipes with ingredients, steps, tags, and metadata.
- **Import-ready recipes** — Structured preparation, freezer, troubleshooting, and variation notes; decimal quantities; and stable step-to-ingredient links.
- **Recipe photos** — Optional R2 uploads with photo credit, source, license, and approximate-match labels.
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
| `R2_ENDPOINT` | S3 API endpoint, such as `https://ACCOUNT_ID.r2.cloudflarestorage.com` |
| `R2_BUCKET` | Bucket for recipe photos |
| `R2_ACCESS_KEY_ID` | Bucket-scoped R2 access key; set securely in deployment secrets |
| `R2_SECRET_ACCESS_KEY` | R2 secret access key; set securely in deployment secrets |

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

### Import recipe cards

Use separate `prep_ahead`, `troubleshooting`, `variations`, and `freezer_notes` fields. Set `freezer_friendly` to enable the freezer-only filter. Keep other notes in `notes`. `source_conversation_url` links a recipe to its original chat.

The server assigns ingredient and step positions from array order on every array write. Existing records with tied positions retain their stored positions: the migration cannot recover an original order that was never recorded. Read those recipes and resubmit their arrays in the intended order after checking the source. The migration preserves existing notes and quantity text, and backfills decimal values for recognized numbers and fractions. It doesn't infer structured advice from free text.

For new ingredients, use `quantity_value` for the numeric amount and optional `quantity_text` for display text. For example, send `0.5` and `"1/2"`. For `"to taste"`, leave `quantity_value` null. Calculations use decimal arithmetic; displayed amounts round to six decimal places. The legacy `quantity` field is still accepted when structured quantity fields are omitted, and remains in responses for older clients. Aggregation combines matching names and units; it doesn't convert units or infer equivalent ingredient names.

Give each ingredient a unique `ref` within its recipe. Preserve that reference on updates. Steps list the references they use in `ingredient_refs`. An inline `{{ref}}` placeholder displays the ingredient's current quantity, unit, and name in the recipe and cook mode. Each placeholder must also appear in that step's `ingredient_refs`. A reference uses the full ingredient amount; for split allocations, use separate ingredient rows with distinct references.

For example, this body creates a recipe with a linked ingredient:

```json
{
  "title": "Roast broccoli",
  "servings": 2,
  "prep_ahead": "Chop the broccoli the day before.",
  "freezer_friendly": false,
  "ingredients": [
    {"ref": "broccoli", "name": "broccoli", "quantity_value": 250, "unit": "g"}
  ],
  "steps": [
    {"short_title": "Roast the veg", "instruction": "Roast {{broccoli}} until tender.", "ingredient_refs": ["broccoli"]}
  ]
}
```

Omitted references are generated by the server. Existing steps without links continue to work. A `PATCH` that removes referenced ingredients must also update the affected steps in the same request. Use `GET /api/v1/recipes?freezer_friendly=true` to list freezer-friendly recipes.

### Configure owned photo storage

The Phoenix app runs on Fly.io. It writes photos directly to R2 through its S3 API; it doesn't need a Worker.

1. Create a private R2 bucket for cookbook photos. Leave public access disabled; no custom domain or browser CORS configuration is needed.
2. Create an R2 credential with **Object Read & Write** access scoped to this bucket.
3. In Fly's secure deployment settings, set the four `R2_*` variables listed above. Enter credentials there, not in chat, recipe bodies, or committed files. The signing region is `auto`.
4. Deploy or restart the app to load the configuration. Upload one permitted photo and verify that the returned `image_url` loads while you're signed into the cookbook and doesn't load in a signed-out browser.

Send `POST /api/v1/recipes/{id}/image` as `multipart/form-data` with a `file` part. Include `image_credit`, `image_source_url`, and `image_license`. Optionally set `image_match` to `exact` or `approximate`. Only upload photos whose license permits the intended use, including any provider-specific conditions. A credit alone doesn't grant permission.

Uploads require the owner's API token and accept JPEG, PNG, or WebP files up to 5,000,000 bytes. The server checks file signatures instead of trusting filenames or declared MIME types. It uses owner- and recipe-scoped content hashes for storage keys, so retries of the same file don't create different keys. Uploads return `503` with `storage_unavailable` when R2 is unconfigured or unavailable, without changing the recipe. They never fetch an arbitrary remote image URL.

Uploaded photos use cookbook URLs backed by authenticated image delivery. The app signs requests to the private bucket; its image routes require the owner's browser session and send `Cache-Control: no-store`. External `image_url` values remain supported, along with attribution fields, but aren't made private by the cookbook. The recipe detail displays credits, license text, photo source, and approximate-match labels. Replacing a photo or deleting a recipe doesn't delete older objects from R2; unused objects need separate cleanup. A failed database update after a successful object upload can also leave an unused object.

After changing the API, regenerate `priv/openapi.json` and refresh the imported OpenAPI source in Speakeasy before the 63-recipe sync. First validate one complete recipe through the real connection, including a scaled step and a licensed photo. Local tests don't verify R2 credentials or generated MCP tool updates.

## License

Private project.

# Cookbook - Recipe Rotation Planner: Build Plan

## Decisions Summary

| Decision       | Choice                          |
| -------------- | ------------------------------- |
| Framework      | Phoenix LiveView                |
| Database       | PostgreSQL                      |
| LLM            | Anthropic Claude API            |
| Auth           | Magic link (email, single-user) |
| Meal structure | Lunch + Dinner x 7 days        |
| Planning scope | Rolling calendar                |
| Deployment     | Deferred                        |
| Cookidoo       | Deferred to v2                  |

---

## Architecture Overview

```
┌─────────────────────────────────────────────┐
│               Phoenix LiveView              │
│  ┌──────────┐ ┌──────────┐ ┌─────────────┐ │
│  │ Recipes  │ │  Planner │ │  Shopping   │ │
│  │  CRUD    │ │ Calendar │ │    List     │ │
│  └────┬─────┘ └────┬─────┘ └──────┬──────┘ │
│       │             │              │        │
│  ┌────┴─────────────┴──────────────┴──────┐ │
│  │              Ecto / Contexts            │ │
│  └────┬─────────────┬─────────────────────┘ │
│       │             │                       │
│  ┌────┴────┐  ┌─────┴──────┐               │
│  │ Postgres│  │ Claude API │               │
│  └─────────┘  └────────────┘               │
└─────────────────────────────────────────────┘
```

Single Elixir app. No microservices. LiveView handles all UI — no separate JS frontend.

---

## Data Model

### `users`
| Column       | Type        | Notes                      |
| ------------ | ----------- | -------------------------- |
| id           | uuid (PK)   |                            |
| email        | string      | unique, only allowed email |
| inserted_at  | timestamp   |                            |
| updated_at   | timestamp   |                            |

### `login_tokens`
| Column       | Type        | Notes                     |
| ------------ | ----------- | ------------------------- |
| id           | uuid (PK)   |                           |
| user_id      | uuid (FK)   |                           |
| token        | string      | hashed, unique            |
| expires_at   | timestamp   | short-lived (~10 min)     |
| used_at      | timestamp   | nullable, set on use      |

### `recipes`
| Column            | Type         | Notes                                  |
| ----------------- | ------------ | -------------------------------------- |
| id                | uuid (PK)    |                                        |
| user_id           | uuid (FK)    |                                        |
| title             | string       |                                        |
| description       | text         | nullable                               |
| servings          | integer      | nullable                               |
| prep_time_minutes | integer      | nullable                               |
| cook_time_minutes | integer      | nullable                               |
| total_time_minutes| integer      | computed or stored                     |
| source_url        | string       | nullable, original URL if scraped      |
| source_type       | enum         | `manual`, `scraped`, `generated`       |
| tags              | text[]       | PostgreSQL array for simple tagging    |
| image_url         | string       | nullable                               |
| notes             | text         | nullable, personal notes               |
| inserted_at       | timestamp    |                                        |
| updated_at        | timestamp    |                                        |

### `ingredients`
| Column       | Type        | Notes                              |
| ------------ | ----------- | ---------------------------------- |
| id           | uuid (PK)   |                                    |
| recipe_id    | uuid (FK)   |                                    |
| name         | string      | e.g. "chicken breast"              |
| quantity     | string      | e.g. "2", "1/2" (kept as string)   |
| unit         | string      | nullable, e.g. "cups", "g", "tbsp" |
| group_name   | string      | nullable, e.g. "For the sauce"     |
| position     | integer     | ordering within recipe             |

### `steps`
| Column       | Type        | Notes                    |
| ------------ | ----------- | ------------------------ |
| id           | uuid (PK)   |                          |
| recipe_id    | uuid (FK)   |                          |
| position     | integer     | step order               |
| instruction  | text        | the step text            |
| duration_minutes | integer | nullable, estimated time |

### `meal_plans`
| Column       | Type        | Notes                               |
| ------------ | ----------- | ----------------------------------- |
| id           | uuid (PK)   |                                     |
| user_id      | uuid (FK)   |                                     |
| week_start   | date        | Monday of the week, unique per user |
| notes        | text        | nullable                            |
| inserted_at  | timestamp   |                                     |
| updated_at   | timestamp   |                                     |

Unique index on `(user_id, week_start)`.

### `meal_plan_entries`
| Column       | Type        | Notes                           |
| ------------ | ----------- | ------------------------------- |
| id           | uuid (PK)   |                                 |
| meal_plan_id | uuid (FK)   |                                 |
| recipe_id    | uuid (FK)   |                                 |
| day_of_week  | integer     | 1 (Mon) through 7 (Sun)        |
| meal_type    | enum        | `lunch`, `dinner`               |
| position     | integer     | ordering if multiple per slot   |

Unique index on `(meal_plan_id, day_of_week, meal_type, position)`.

---

## Project Phases

The project is split into **5 phases** that can be partially parallelized. Each phase is described as a self-contained work package an agent can pick up.

---

### Phase 1: Project Scaffold & Auth

**Goal**: Bootable Phoenix app with PostgreSQL, magic-link auth, and a protected layout.

**Tasks**:
1. Generate Phoenix project: `mix phx.new cookbook --live --binary-id`
2. Configure PostgreSQL in `config/dev.exs` and `config/test.exs`
3. Add dependencies to `mix.exs`:
   - `swoosh` + `gen_smtp` (email delivery, already included by default)
   - `tailwind` (already included by default)
4. Create migrations:
   - `users` table
   - `login_tokens` table
5. Create `Cookbook.Accounts` context:
   - `get_or_create_user_by_email/1` — only allows a whitelisted email (configurable via env `ALLOWED_EMAIL`)
   - `create_login_token/1` — generates a random token, stores hashed version, returns raw token
   - `verify_login_token/1` — looks up, checks expiry, marks used, returns user
6. Create auth plug/on_mount:
   - `CookbookWeb.Auth` — LiveView `on_mount` hook that checks session for `user_id`
   - Redirect to `/login` if unauthenticated
7. Create LiveView pages:
   - `LoginLive` — email input form, sends magic link email
   - `AuthCallbackController` — GET `/auth/callback?token=X`, verifies token, sets session, redirects to `/`
8. Configure Swoosh for dev (local mailbox adapter) and prod (env-configured SMTP or Resend/Postmark)
9. Add a root layout with nav bar (placeholder links for Recipes, Planner)
10. Write tests for the Accounts context and auth flow

**Outputs**: Working app with login. Visiting `/` redirects to `/login` if not authed. After login, shows empty dashboard.

**Env vars**:
- `ALLOWED_EMAIL` — the single email address allowed to log in
- `SECRET_KEY_BASE`
- `DATABASE_URL`

---

### Phase 2: Recipe CRUD

**Goal**: Full recipe management — create, read, update, delete recipes with ingredients and steps.

**Depends on**: Phase 1 (auth, DB, layout)

**Tasks**:
1. Create migrations:
   - `recipes` table
   - `ingredients` table
   - `steps` table
2. Create `Cookbook.Recipes` context:
   - `list_recipes/1` — paginated, filterable by tag, searchable by title
   - `get_recipe!/1` — preloads ingredients and steps
   - `create_recipe/1` — accepts nested ingredients/steps
   - `update_recipe/2` — updates recipe, syncs nested ingredients/steps
   - `delete_recipe/1`
   - `search_recipes/1` — full-text search on title + ingredient names
3. Create LiveView pages:
   - `RecipeListLive` — grid/list view of all recipes with search bar and tag filter
   - `RecipeShowLive` — full recipe view with ingredients, steps, times, tags
   - `RecipeFormLive` — create/edit form with:
     - Dynamic ingredient rows (add/remove, reorder via drag or buttons)
     - Dynamic step rows (add/remove, reorder)
     - Tag input (comma-separated or pill-style)
     - Image URL field
4. Use `Ecto.Multi` for atomic recipe creation/updates with nested assocs
5. Add recipe card component for the list view (title, image, time, tags)
6. Write tests for the Recipes context

**UI notes**:
- Clean, modern design with Tailwind
- Recipe cards in a responsive grid (1 col mobile, 2-3 cols desktop)
- Form should feel fluid — no page reloads

**Outputs**: Full recipe CRUD at `/recipes`, `/recipes/new`, `/recipes/:id`, `/recipes/:id/edit`.

---

### Phase 3: LLM Integration (Recipe Scraping & Generation)

**Goal**: Scrape recipes from URLs and generate recipes from prompts using Claude API.

**Depends on**: Phase 2 (recipe data model)

**Tasks**:
1. Add `req` HTTP client dependency (for Claude API calls and URL fetching)
2. Create `Cookbook.AI` context:
   - `scrape_recipe_from_url/1`:
     - Fetch the URL HTML content using Req
     - Send HTML to Claude with a structured prompt asking for JSON output matching the recipe schema (title, description, servings, prep_time, cook_time, ingredients[], steps[])
     - Parse Claude's response and return a recipe changeset
   - `generate_recipe/1`:
     - Accept a free-text prompt (e.g. "a quick pasta dish with mushrooms")
     - Send to Claude asking for a structured recipe JSON
     - Parse and return recipe changeset
   - `suggest_weekly_plan/2`:
     - Accept user preferences / constraints (e.g. "healthy", "varied", existing recipe pool)
     - Ask Claude to pick/arrange recipes into a lunch+dinner x 7-day plan
     - Return a structured plan
3. Create a `Cookbook.AI.Client` module:
   - Wraps Claude API HTTP calls (messages endpoint)
   - Uses `ANTHROPIC_API_KEY` env var
   - Handles rate limiting, retries, error handling
   - Formats system prompts and extracts structured JSON from responses
4. Define Claude system prompts as module attributes or config:
   - Scraping prompt: extract recipe data from raw HTML
   - Generation prompt: create a recipe given user input
   - Planning prompt: suggest a weekly meal plan
5. Integrate into the recipe form:
   - Add "Import from URL" tab to `RecipeFormLive` — paste URL, show loading spinner, prefill form with scraped data (user can edit before saving)
   - Add "Generate with AI" tab — text input for prompt, generate, prefill form
6. Add async handling:
   - LLM calls are slow (~5-15s). Use `Task.async` or `send(self(), ...)` pattern in LiveView to keep UI responsive with a loading state
7. Write tests with mocked Claude responses

**Env vars**:
- `ANTHROPIC_API_KEY`

**Outputs**: Recipe form has 3 tabs: Manual, Import from URL, Generate with AI. All produce editable recipe data before saving.

---

### Phase 4: Meal Planner (Calendar)

**Goal**: Rolling weekly calendar where users assign recipes to lunch/dinner slots.

**Depends on**: Phase 2 (recipes), Phase 3 (AI plan suggestions)

**Tasks**:
1. Create migrations:
   - `meal_plans` table
   - `meal_plan_entries` table
2. Create `Cookbook.Planner` context:
   - `get_or_create_plan_for_week/2` — finds or creates a meal plan for a given week_start
   - `list_plans/1` — list all plans for a user, ordered by week
   - `add_entry/2` — assign a recipe to a day+meal slot
   - `remove_entry/1` — remove a recipe from a slot
   - `move_entry/2` — move a recipe to a different slot (drag & drop support)
   - `generate_shopping_list/1` — aggregate all ingredients from a plan's recipes, merge duplicates by ingredient name
3. Create LiveView pages:
   - `PlannerLive` — the main calendar view:
     - Week navigation (prev/next week buttons, "today" button)
     - 7-column grid (Mon-Sun), 2 rows per day (Lunch, Dinner)
     - Each cell shows assigned recipe card(s) or empty state with "+" button
     - Click "+" opens a recipe picker modal (searchable list of all recipes)
     - Drag & drop to rearrange recipes between slots (LiveView JS hooks)
     - "Suggest plan" button — calls AI to auto-fill empty slots
   - `ShoppingListLive` — for a given week:
     - Aggregated, de-duplicated ingredient list
     - Checkboxes to mark items as "got it"
     - Grouped by category if possible (produce, dairy, meat, pantry)
4. Add a `PlannerComponent` for the week grid (reusable)
5. Recipe picker modal — searchable, shows recipe cards, click to assign
6. Week navigation with URL params (`/planner?week=2026-02-23`)
7. Write tests for the Planner context

**UI notes**:
- Calendar should look clean and scannable
- Mobile: stack days vertically
- Desktop: 7-column grid
- Drag & drop is nice-to-have; fallback is move via dropdown/buttons

**Outputs**: Full planner at `/planner`, shopping list at `/planner/shopping?week=X`.

---

### Phase 5: Polish & UX

**Goal**: Design refinement, quality-of-life features, production readiness.

**Depends on**: Phases 1-4

**Tasks**:
1. **Design system**:
   - Define color palette, typography, spacing using Tailwind config
   - Consistent component styles (buttons, cards, modals, forms, inputs)
   - Dark mode support (optional, low priority)
2. **Dashboard** (`/`):
   - Show current week's plan summary
   - Quick links: "Plan this week", "Add recipe", "Shopping list"
   - Stats: total recipes, this week's plan status
3. **Recipe parallelization hint**:
   - When viewing a day's meals, show a "cooking timeline" if both lunch and dinner have time data
   - Simple visual: "Start Recipe A at 12:00, while it bakes start Recipe B at 12:30"
   - Uses `prep_time_minutes`, `cook_time_minutes`, and step `duration_minutes`
4. **Flash messages & error handling**:
   - Friendly error messages for LLM failures
   - Success toasts for CRUD operations
5. **Responsive design audit**:
   - Test all pages at mobile, tablet, desktop breakpoints
   - Fix any overflow or layout issues
6. **SEO / Meta**:
   - Not critical (private app), but add proper page titles
7. **Production config**:
   - `config/runtime.exs` for env-based config
   - `Dockerfile` (multi-stage Elixir release build)
   - `fly.toml` or `docker-compose.yml` placeholder
   - Health check endpoint (`/health`)
8. **CI** (optional):
   - GitHub Actions: `mix test`, `mix format --check-formatted`, `mix credo`

**Outputs**: Polished, production-ready app.

---

## Agent Parallelization Strategy

```
Timeline:
─────────────────────────────────────────────────────

Agent A:  [Phase 1: Scaffold & Auth]──────►
Agent B:                                    [Phase 2: Recipe CRUD]──────►
Agent C:                                                  [Phase 3: LLM Integration]──►
Agent D:                                                  [Phase 4: Meal Planner]──────►
Agent E:                                                                    [Phase 5: Polish]──►
```

- **Phase 1** must complete first (other phases depend on the app skeleton + auth).
- **Phase 2** must complete before Phases 3 and 4 (they depend on the recipe model).
- **Phases 3 and 4** can run **in parallel** — they touch different contexts and LiveViews.
- **Phase 5** runs last to polish the integrated result.

Within phases, tasks are ordered but an agent can work through them sequentially.

---

## File Structure (Expected)

```
cookbook/
├── config/
│   ├── config.exs
│   ├── dev.exs
│   ├── test.exs
│   ├── prod.exs
│   └── runtime.exs
├── lib/
│   ├── cookbook/
│   │   ├── accounts/           # Phase 1
│   │   │   ├── user.ex
│   │   │   └── login_token.ex
│   │   ├── accounts.ex         # Phase 1 context
│   │   ├── recipes/            # Phase 2
│   │   │   ├── recipe.ex
│   │   │   ├── ingredient.ex
│   │   │   └── step.ex
│   │   ├── recipes.ex          # Phase 2 context
│   │   ├── planner/            # Phase 4
│   │   │   ├── meal_plan.ex
│   │   │   └── meal_plan_entry.ex
│   │   ├── planner.ex          # Phase 4 context
│   │   ├── ai/                 # Phase 3
│   │   │   ├── client.ex
│   │   │   └── prompts.ex
│   │   └── ai.ex               # Phase 3 context
│   ├── cookbook_web/
│   │   ├── components/
│   │   │   ├── layouts/
│   │   │   ├── recipe_card.ex
│   │   │   └── core_components.ex
│   │   ├── live/
│   │   │   ├── login_live.ex
│   │   │   ├── dashboard_live.ex
│   │   │   ├── recipe_list_live.ex
│   │   │   ├── recipe_show_live.ex
│   │   │   ├── recipe_form_live.ex
│   │   │   ├── planner_live.ex
│   │   │   └── shopping_list_live.ex
│   │   ├── controllers/
│   │   │   └── auth_controller.ex
│   │   └── router.ex
│   └── cookbook_web.ex
├── priv/
│   └── repo/migrations/
├── test/
│   ├── cookbook/
│   │   ├── accounts_test.exs
│   │   ├── recipes_test.exs
│   │   ├── planner_test.exs
│   │   └── ai_test.exs
│   └── cookbook_web/live/
├── mix.exs
├── mix.lock
└── Dockerfile
```

---

## Key Design Decisions Made

1. **Single-user by design** — no multi-tenancy complexity, but `user_id` FKs are still present for clean data modeling and future-proofing.
2. **Ingredients as separate table** (not JSONB) — enables shopping list aggregation via SQL and proper searching.
3. **Steps as separate table** — enables per-step duration tracking for the parallelization feature.
4. **`source_type` enum** — tracks how each recipe was created for potential analytics/filtering.
5. **`week_start` as date** — always normalized to Monday, makes week navigation simple.
6. **Quantity as string** — avoids precision issues with fractions like "1/2", "2-3", etc.
7. **Claude structured output** — all LLM calls request JSON responses matching our schema, parsed and validated before creating records.
8. **Shopping list is computed** — not stored, generated on-the-fly from plan entries. Keeps data normalized.

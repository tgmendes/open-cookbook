# Private Cookbook API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Do not dispatch agents without explicit authorization.

**Goal:** Let the owner use Claude through authenticated Speakeasy MCP tools to maintain their cookbook, while preserving the app as a cooking and planning dashboard.

**Architecture:** Keep browser sign-in separate from API credentials. Cookbook will authenticate API calls with revocable owner-bound tokens; Speakeasy will handle the Claude-facing OAuth connection. Hosted MCP creation from OpenAPI and secure credential entry require a dashboard step because the available Platform MCP does not expose those operations.

**Tech Stack:** Existing Elixir, Phoenix 1.8, LiveView, Ecto, PostgreSQL, Req, and Speakeasy AI Control Plane.

**Spec:** Scope, technical direction, location, and Group 1 approved in this conversation on 2026-11-13. The user subsequently authorized routine decisions without further prompts and requested implementation. Remaining groups below record those implementation decisions; critical security and external setup confirmations still apply.

## Global Constraints

- Personal-first: only the configured allowed email may access the app or authorize cookbook access.
- Derive ownership from authenticated identity, never from a caller-supplied user ID.
- Preserve existing recipes, plans, shopping-list generation, and cooking walkthroughs.
- Remove embedded OpenRouter features in a later task group.
- No public access or sharing; verify Speakeasy access separately from upstream credentials.
- Never include credentials in chat, source control, logs, or planning artifacts.
- Do not implement, commit, deploy, publish, or mutate platform configuration based on plan approval alone. The user has requested implementation; remaining plan checkpoints still apply.
- Use repository conventions, test-first implementation, generated migrations, and `mix precommit` for final verification.

## Review Focus

- Concurrent use of a magic link must yield only one successful login.
- Changing or removing the allowed email must invalidate access for previously authenticated identities.
- API credentials must never be accepted as browser magic links, or vice versa.
- Expired and revoked API tokens must fail identically to unknown tokens.
- Token listing and revocation must be owner-scoped; raw secrets must not reappear after their creation response.

## Investigation Evidence

- `lib/cookbook/accounts.ex` restricts user creation by email and stores hashed ten-minute login tokens. Consumption currently reads and then updates without an atomic claim.
- `lib/cookbook_web/auth.ex` trusts the session's user ID and does not currently recheck the email allowlist or enforce an authentication timestamp.
- `lib/cookbook_web/controllers/auth_controller.ex` renews the session on login and exposes logout through GET.
- `lib/cookbook_web/live/login_live.ex` ignores the result of email delivery before showing the sent state.
- `lib/cookbook_web/router.ex` has a JSON pipeline but no cookbook API endpoints.
- `lib/cookbook_web.ex` currently configures the app layout automatically; new explicit layout wrappers must avoid double wrapping.
- `lib/cookbook_web/components/layouts.ex` currently uses `@inner_content`; any slot-based use must also support `render_slot(@inner_block)` without breaking existing views.
- Speakeasy documentation describes separate upstream credential modes and Claude-facing authentication. The available Platform MCP can discover and manage servers, but does not expose creation of OpenAPI sources or secret credential entry.
- Source inspection only: no tests have been run. The engineering-library search failed because a stored document was missing; no library repair was attempted.

---

## Group 1: Private Authentication and API Credentials

**Status:** Approved, including 30-day browser sessions and 90-day API token expiry.

### Task 1: Harden app authentication

**Files:**
- Modify: `lib/cookbook/accounts.ex`
- Modify: `lib/cookbook_web/auth.ex`
- Modify: `lib/cookbook_web/controllers/auth_controller.ex`
- Modify: `lib/cookbook_web/live/login_live.ex`
- Modify: `lib/cookbook_web/components/layouts.ex` for CSRF-protected logout links
- Modify: `lib/cookbook_web/router.ex`
- Modify: `test/cookbook/accounts_test.exs`
- Modify: `test/cookbook_web/controllers/auth_controller_test.exs`
- Create (proposed): `test/cookbook_web/auth_test.exs`
- Create (proposed): `test/cookbook_web/live/login_live_test.exs`

**Interfaces:**
- Preserve `Accounts.verify_login_token(raw_token)` returning `{:ok, user}` or `{:error, :invalid_token}`.
- Propose `Accounts.authorized_user?(user)` as the shared allowlist predicate; nil or missing configuration denies access.
- Browser authentication continues to identify the user through the session, with an added authentication timestamp checked by both HTTP and LiveView authentication.

- [x] Write failing tests for malformed, expired, reused, and concurrently consumed magic links; missing callback parameters; expired sessions; and users whose email is no longer allowed.
- [x] Test email-delivery failures without asserting a successful send; retain a non-enumerating response for unauthorized addresses.
- [x] Run the focused tests and verify the new assertions fail for the intended reasons.
- [x] Make login-token consumption atomic and recheck the allowed email before returning the user.
- [x] Clear and renew the session at login. Enforce the proposed 30-day lifetime in HTTP and LiveView authentication, with missing or malformed timestamps denied. Existing sessions without a timestamp require signing in again.
- [x] Replace GET logout with a CSRF-protected action and update the layout and controller tests.
- [x] Handle email-delivery errors without claiming a link was sent.
- [x] Run `mix test test/cookbook/accounts_test.exs test/cookbook_web/controllers/auth_controller_test.exs test/cookbook_web/auth_test.exs test/cookbook_web/live/login_live_test.exs`; expect all focused tests to pass.

### Task 2: Add revocable API tokens

**Dependency:** Task 1's shared allowlist predicate.

**Files:**
- Create (proposed): `lib/cookbook/accounts/api_token.ex`
- Generate: `priv/repo/migrations/<generated_timestamp>_create_api_tokens.exs` with `mix ecto.gen.migration create_api_tokens`
- Modify: `lib/cookbook/accounts.ex`
- Create (proposed): `test/cookbook/api_tokens_test.exs`

**Proposed interfaces in `Cookbook.Accounts`:**
- `create_api_token(user, name)` returns `{:ok, token_record, raw_token}` or `{:error, reason}`.
- `authenticate_api_token(raw_token)` returns `{:ok, user}` or `{:error, :unauthorized}`.
- `list_api_tokens(user)` returns token metadata only.
- `revoke_api_token(user, token_id)` returns `:ok` or `{:error, :not_found}`.

- [x] Write tests for creation, metadata-only listing, authentication, expiry, revocation, malformed inputs, allowlist changes, cross-owner operations, and separation from magic-link tokens.
- [x] Assert the stored token hash differs from the raw token and that ownership cannot be supplied through token attributes.
- [x] Run `mix test test/cookbook/api_tokens_test.exs`; expect failures from missing token functionality.
- [x] Generate 32 random bytes per token. Store only its SHA-256 hash, owner, name, expiry, and revocation status, with a unique hash index and an owner index.
- [x] Set ownership on the struct rather than casting user input. Use the proposed 90-day expiry and deny expired, revoked, malformed, and no-longer-authorized credentials uniformly.
- [x] Implement owner-scoped metadata listing and revocation without exposing stored hashes to the view.
- [x] Run `mix test test/cookbook/api_tokens_test.exs`; expect all token tests to pass.

### Task 3: Add connection settings

**Dependency:** Task 2's token interfaces and Task 1's authenticated browser session.

**Files:**
- Create (proposed): `lib/cookbook_web/live/api_token_live.ex`
- Create (proposed): `test/cookbook_web/live/api_token_live_test.exs`
- Modify: `lib/cookbook_web/router.ex`
- Modify: `lib/cookbook_web/components/layouts.ex`

**Interfaces:**
- Add authenticated `/settings/connections` inside the existing authenticated live session.
- Use Task 2's account interfaces for all token operations; never trust an owner ID from an event.

- [x] Write LiveView tests for anonymous access, token creation, invalid names, owner-scoped revocation, and absence of raw secrets on subsequent visits.
- [x] Add stable DOM IDs for the creation form, newly generated token panel, token metadata rows, and revoke buttons; assert against those IDs with LiveViewTest.
- [x] Run `mix test test/cookbook_web/live/api_token_live_test.exs`; expect failures from the missing page.
- [x] Implement token creation, metadata listing, and revocation. Render the raw secret only in the creation response, clear it on dismissal or subsequent actions, and never persist it for retrieval.
- [x] Prevent caching of the connection settings response and keep token values out of event payloads and logs.
- [x] Use an explicit `Layouts.app` wrapper with the current scope, without double wrapping; maintain compatibility for existing app-layout callers.
- [x] Run `mix test test/cookbook_web/live/api_token_live_test.exs`; expect all page tests to pass.

## Group 2: Owner-scoped Cookbook API

### Task 4: Implement the authenticated API and contract

**Dependency:** Group 1 token authentication.

**Files:**
- Modify: `lib/cookbook/recipes.ex`, `lib/cookbook/planner.ex`, and affected recipe/planner schemas.
- Modify: existing recipe/planner LiveViews and tests to use owner-scoped operations.
- Modify: `lib/cookbook_web/router.ex`.
- Create: `lib/cookbook_web/controllers/api_auth.ex`, `cookbook_api_controller.ex`, and `cookbook_json.ex` in `lib/cookbook_web/controllers/`.
- Create: `lib/cookbook/api_requests.ex` and `lib/cookbook/api_request.ex`; generate the API receipt migration with Mix.
- Create: `priv/openapi.json` and `test/cookbook_web/controllers/cookbook_api_controller_test.exs`.

**Proposed HTTP interfaces, all requiring Bearer authentication:**
- `GET /api/v1/profile`: unit preference and accepted ingredient units, without email or credential data.
- `GET /api/v1/recipes`: search/tag filters and bounded pagination (default 50, maximum 100).
- `POST /api/v1/recipes`: nested recipe creation; require an `Idempotency-Key` of 1–128 characters. Persist owner-scoped request fingerprints and original JSON responses for 24 hours. Replays return the original response; changed bodies under the same key return 409.
- `GET /api/v1/recipes/:id`: full recipe, ordered ingredients, and ordered steps.
- `PATCH /api/v1/recipes/:id`: partial scalar updates; supplied ingredient/step arrays replace that entire collection, omitted collections remain unchanged.
- `DELETE /api/v1/recipes/:id`: delete the owner's recipe and its existing meal-plan references, matching existing database behavior; tool description must disclose that effect.
- `GET /api/v1/meal-plans/:week`: normalize an ISO date to Monday; return an empty plan without writing if absent.
- `PUT /api/v1/meal-plans/:week/slots/:day/:meal`: atomically replace only this slot with ordered `recipe_ids`; empty arrays clear it. Days are 1–7, meals lunch/dinner. Repetition has the same result without duplicate entries.
- `GET /api/v1/shopping-lists/:week`: aggregate the owner's planned recipes without writing. Checkmarks remain browser-session-only; no new cross-client persistence is implied.

**Responses:** JSON `data` envelope for reads/writes; 204 for deletion. Uniform JSON errors: 401 for invalid credentials (no cookie fallback), 404 for unknown/cross-owner/malformed resource IDs, 422 for invalid input, and 409 for idempotency conflicts. Never serialize Ecto structs wholesale or accept user/parent IDs from request bodies.

- [x] Write controller/context tests covering valid operations, absent/invalid/revoked tokens, cross-owner IDs, forged ownership, malformed nested input, negative times/servings, pagination, and unknown keys.
- [x] Test recipe creation replay, conflicting keys, and concurrent matching creates; test PATCH omission versus explicit empty collections.
- [x] Test slot replacement rollback on an invalid/foreign recipe, Monday normalization, unrelated-slot preservation, empty reads without writes, and shopping aggregation of repeated recipes.
- [x] Run focused tests and confirm the missing behavior fails.
- [x] Implement scoped domain interfaces, explicit JSON serialization, token-only pipeline, input validation, and transactional write receipts/slot replacement. Remove unscoped domain entry points after migrating internal callers/tests.
- [x] Write OpenAPI 3.0.3 with matching schemas, errors, Bearer security, stable operation IDs, and destructive/replacement semantics. Include the idempotency header in the create operation.
- [x] Run controller/context tests and assert OpenAPI operation coverage against router endpoints, required authentication, and representative response shapes.

## Group 3: Dashboard Without Embedded AI

### Task 5: Replace embedded AI creation with manual editing

**Files:**
- Modify: `lib/cookbook_web/live/recipe_form_live.ex`, `planner_live.ex`, dashboard/list copy, `config/config.exs`, `config/runtime.exs`, and `README.md`.
- Remove: `lib/cookbook/ai.ex`, its AI-only files under `lib/cookbook/ai/`, and `test/cookbook/ai_test.exs` after verifying all callers are removed.
- Create: `test/cookbook_web/live/cookbook_live_test.exs`.

- [x] Write LiveView tests for manual create/edit with ingredients and steps, owner-only show/cook/delete access, dashboard/planner/shopping views, and absence of embedded generation controls.
- [x] Run tests to observe the missing manual-first behavior.
- [x] Simplify the recipe form, remove OpenRouter event/task/config paths, retain source metadata on old recipes, and preserve catalog/cook/planner/shopping functionality.
- [x] Use explicit layout wrappers for changed templates and maintain existing layout compatibility elsewhere.
- [x] Run LiveView tests and the complete test suite.

## Group 4: Verification and Secure Setup Handoff

### Task 6: Document deployment and verify the local deliverable

**Files:** `README.md`, `docs/speakeasy-setup.md`, this plan.

- [x] Document additive migrations, API token creation/rotation/revocation, idempotency behavior, and OpenAPI import into Speakeasy.
- [x] Clearly separate app deployment, adding the hosted MCP to the project, secure upstream credential entry, Claude OAuth connection, and verifying access is limited to the owner. Do not distribute to a plugin or assume private visibility alone limits access to one member.
- [x] Run `mix precommit`, review the full diff, and address significant findings with regression tests.
- [x] Record actual verification results and any blocked external setup. Do not deploy, publish, or enter credentials without the exact required authorization and secure channel.

## Execution Record

- Ruling: Continue routine technical decisions without more review pauses, per the user's explicit instruction. No authorization to expose a public server, share credentials, or broaden access is inferred.
- Ruling: Work in the native `private-cookbook-api` worktree rather than editing `main`; leave changes uncommitted unless requested.
- Ruling: Keep the progress ledger in this plan rather than a disposable commit-based workspace, since commits are not authorized and the plan already carries the task checklists.
- Pre-flight: Tasks 1–3 share `authorized_user?/1` and the token lifecycle interfaces; Task 4 consumes token authentication and scopes all domain calls. Task 5 consumes the scoped domain calls. No interface conflict found.

### Local execution results

- Tasks 1–3: complete. The initial combined auth tests produced 17 failures, including two successful concurrent consumers of one magic link. Atomic consumption, session expiry/allowlist checks, token lifecycle, delivery failure handling, and the connection settings tests subsequently passed.
- Task 4: complete. All 14 initial API tests failed before implementation; authenticated API tests subsequently passed, including concurrent recipe creation, owner isolation, and slot replacement. The OpenAPI route test also failed before implementation and passed afterward.
- Task 5: complete. Manual editing, nested content removal/reindexing, catalog, dashboard, planner, shopping list, cook navigation, and local serving scaling have passing tests. No OpenRouter modules/configuration remain in application code.
- Task 6: local documentation and review complete. External deployment and Speakeasy setup are NOT complete.
- Final review: self-review; no reviewer agent was dispatched. Cubic's learned-pattern tools were not available. This is not an independent review.
- Review regressions fixed RED→GREEN: unsafe recipe URLs/null tags, ingredient ordering after removing and adding rows, cross-owner recipes linked by legacy meal entries, and editing a recipe deleted concurrently.
- Verification: final `mix precommit` passed with 83 tests and 0 failures. `MIX_ENV=prod mix compile --warnings-as-errors` also passed.
- OpenAPI: exported with `mix cookbook.openapi`; Speakeasy CLI validation passed with 0 errors, 0 warnings, and 66 nonblocking generation hints. This was local validation, not a platform deployment.
- JavaScript: `MIX_ENV=test mix esbuild cookbook` passed.
- CSS build issue resolved on 2026-11-14: macOS crash diagnostics identified `CODESIGNING — Invalid Page` for Tailwind 4.1.12. Its checksum matched the official release, ruling out local download corruption. The official 4.3.5 binary matched its checksum, passed signature verification, and compiled the app's CSS in an isolated trial. After the user authorized the update, `config/config.exs` was pinned to 4.3.5 and installed through Mix. Normal `mix assets.build` now passes for both CSS and JavaScript; `mix precommit` also passes all 83 tests. No OS security controls were bypassed. Visual styling has not been browser-verified.
- Platform: read-only checks found no existing Open Cookbook server in Default. No server, source, plugin, grant, or credential was changed. Deployment and secure setup steps are in `docs/speakeasy-setup.md`.
- Environment: tests used a disposable PostgreSQL 17 container with tmpfs storage bound only to localhost port 5434. It was stopped and automatically removed after verification. Existing app database volumes were not used. The native worktree remains on its managed detached HEAD with all changes uncommitted.

Final planned repository verification is `mix precommit`. Deployment and secure platform setup remain separate from local test results; do not report the MCP as working until an authenticated end-to-end call has been verified.

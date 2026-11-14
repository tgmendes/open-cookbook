# Set up the private Speakeasy connection

Use this setup to let Claude maintain your cookbook while keeping browser sign-in and API credentials separate. The app does not implement an OAuth authorization server: Speakeasy handles Claude's OAuth connection, and the cookbook API validates its own revocable token.

**Status:** The repository contains the API and OpenAPI contract. App deployment, hosted MCP creation, secret entry, and the authenticated Claude connection must be completed and verified separately.

## 1. Deploy the app

1. Review and deploy the changes through your normal deployment process. `fly.toml` names `open-cookbook` and runs migrations through its release command.
2. Set `ALLOWED_EMAIL` to your email. An absent or mismatched value denies access. Configure `RESEND_API_KEY` and an authorized `MAIL_FROM` sender for sign-in emails. Keep secrets in the deployment's secret store.
3. Apply the additive `create_api_tokens` and `create_api_requests` migrations. These do not delete existing recipes or plans.
4. Verify the dashboard's email sign-in, weekly planner, shopping list, recipe editor, and cooking view over HTTPS. Magic-link requests have a one-minute cooldown; wait a minute before retrying a delivery failure. Existing browser sessions must sign in again because they do not have the authentication timestamp.
5. Verify that `/api/v1/profile` returns 401 without a token. The public `/health` and `/api/openapi.json` endpoints contain no cookbook records.

No OpenRouter key is needed. Remove the old deployment secret through your normal secret-management process after confirming no other workload uses it.

## 2. Add the hosted MCP to the project

A Speakeasy project contains the sources and MCP servers you configure. Choose the project deliberately; the Default project can carry organization-wide grants, so its name is not evidence of personal-only access.

1. Import `priv/openapi.json` as an OpenAPI source in Speakeasy, or supply the deployed app's `/api/openapi.json` URL. The exported contract uses `https://open-cookbook.fly.dev`; regenerate it if the deployment address differs.
2. Create a hosted MCP server named **Open Cookbook** from that source. Keep it disabled or otherwise inaccessible while configuring authentication and access.
3. Require user-session sign-in with Speakeasy as the authorization server. Do not allow anonymous calls.
4. Restrict the server's **Team Access** to your identity. Check broader roles and grants to everyone as well as direct grants. If an inherited grant cannot be narrowed safely, stop and resolve it before enabling the server.
5. Review which MCP apps can sign in. Permit Claude as needed; do not widen admission without a reason.

The available Platform MCP can inspect existing servers and their access, but it does not create an OpenAPI source or accept secret credentials. Those steps require the dashboard. Once the server exists, use the Platform MCP to verify its exact configuration instead of guessing from UI labels.

Do not add this server to a plugin, the bundle of MCP servers and instructions shared with other people, unless you intentionally want to share it. A plugin is not required for your own connection.

## 3. Configure the upstream API credential securely

1. Sign into the cookbook and open **Connections** at `/settings/connections`.
2. Create a token named **Claude via Speakeasy**. Copy it while the creation response is visible; the database stores only its hash and cannot recover the secret.
3. Enter it directly in Speakeasy's secure credential settings for the OpenAPI Bearer security scheme, `cookbookToken`. Do not paste it into an AI chat. Use the security scheme's token field rather than a query parameter or a tool argument.
4. Verify the resolved upstream header is `Authorization: Bearer` followed by the token, with the prefix applied once.
5. If the credential is configured as a System environment variable, it is shared by every permitted caller of that server. Confirm owner-only access before enabling it. A private label alone is not sufficient.

Hosted sources can configure environment variables as System, User, or Omit. The exact generated variable name comes from the imported source; do not invent a name. A User variable requires the connecting client to provide it and may appear in install instructions. For this owner-only setup, use secure stored configuration only after verifying who can spend that credential.

Administrative access to Speakeasy and the app's infrastructure remains part of the trust boundary. This setup does not hide cookbook access from administrators who can change server grants, deployment secrets, or the database.

## 4. Connect Claude and verify access

1. Enable the MCP only after authentication, upstream credentials, and owner-only access have been checked.
2. Obtain the exact Claude install instructions for this server through the Platform MCP or dashboard. Add its MCP URL to Claude and complete the Speakeasy OAuth sign-in as yourself.
3. Read the cookbook profile and recipe catalog first. Verify an anonymous request cannot list or invoke cookbook tools. Where a second test identity is available, verify it is denied; do not infer this from your own successful sign-in.
4. Ask Claude to create one clearly named test recipe. Confirm it appears once in the dashboard, including its ingredients and ordered steps. Repeating the request with the same idempotency key and body must return the original result without creating another recipe.
5. Assign that recipe to a meal slot and check the weekly display and shopping list. Confirm changing the slot leaves the other slots intact.
6. Revoke the connection's API token in the app. Calls through Speakeasy must then fail with 401. Create a replacement token, update it securely, and verify access again.

Do not report setup as complete until the real deployed connection passes these checks. Local controller tests do not prove Speakeasy grants or Claude OAuth configuration.

## API behavior to preserve in MCP tools

- Read the profile before generating recipes to respect the unit preference.
- Use a fresh `Idempotency-Key` of 1–128 characters for each intentional recipe creation. Reuse it for the same body on retries for up to 24 hours. A changed body with the same key returns 409.
- Replay returns the original create response, even if that recipe was subsequently edited or deleted. Read the recipe to check its current state.
- Search uses `search` and `tag`. Pagination defaults to 50 recipes, allows at most 100, and returns `meta.has_more` and `meta.offset`.
- `PATCH` preserves omitted fields. Supplied ingredient and step arrays replace the respective collection in array order; send `[]` to clear one.
- Use `PUT` to replace one lunch or dinner slot. Monday is day 1 and Sunday is day 7. Empty `recipe_ids` clears the slot. Read the current slot before appending recipes so existing entries are not lost.
- Deleting a recipe also removes its meal-plan references. Ask the owner before invoking deletion.
- Shopping quantities reflect each planned occurrence of the stored recipe. Browser checkmarks are not persisted or exposed by the API.

## Rotate or roll back

Tokens expire after 90 days. To rotate one, create a replacement, update Speakeasy securely, verify a read, then revoke the previous token. Revocation is immediate for subsequent API requests; changing `ALLOWED_EMAIL` also denies credentials belonging to the previous owner.

If the connection behaves unexpectedly, disable the exact Speakeasy server and revoke its cookbook token first. Keep the additive tables when rolling back app code unless their data is deliberately being discarded. Dropping the token table invalidates all API credentials; dropping the request table loses recipe-create replay protection. Restoring the older app also restores its older authentication behavior, so it is not a security rollback.

## References

- [Speakeasy upstream credentials](https://www.speakeasy.com/docs/ai-control-plane/mcp-gateway/access/upstream-credentials)
- [Speakeasy user-session authentication](https://www.speakeasy.com/docs/ai-control-plane/mcp-gateway/access/user-sessions)
- [Speakeasy team access](https://www.speakeasy.com/docs/ai-control-plane/mcp-gateway/access/team-access)

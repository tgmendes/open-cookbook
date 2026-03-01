# Cookidoo API Research

## Summary

Cookidoo (Vorwerk/Thermomix recipe platform) **does not have an official public API**. Vorwerk has not published developer documentation or opened the platform for third-party integrations. However, the community has reverse-engineered the internal API used by the Cookidoo Android app, and several unofficial tools exist for recipe creation/upload.

---

## Unofficial Tools & Libraries

### 1. `cookiput` (Go CLI) — Best reference for API endpoints

- **Repo**: https://github.com/croeer/cookiput
- Demonstrates the actual HTTP endpoints for creating custom recipes on Cookidoo

#### API Endpoints

**Create a recipe:**
```
POST /created-recipes/{locale}
Body: {"recipeName": "My Awesome New Recipe"}
Response: { "recipeId": "..." }
```

**Update recipe content:**
```
PATCH /created-recipes/{locale}/{recipeId}
```

Supported fields:
```json
{
  "ingredients": [
    {"type": "INGREDIENT", "text": "500g chicken breast"}
  ],
  "instructions": [
    {"type": "STEP", "text": "Preheat oven to 180°C"}
  ],
  "tools": ["TM6"],
  "totalTime": 4200,
  "prepTime": 3900,
  "yield": {"value": 4, "unitText": "portion"}
}
```

Times are in **seconds** (e.g. 3900s = 65 minutes).

#### Authentication
- JWT token from the `_oauth2_proxy` cookie (user logs into Cookidoo in a browser, extracts from dev tools)

---

### 2. `cookidoo-api` (Python, async) — Most actively maintained

- **Repo**: https://github.com/miaucl/cookidoo-api
- **PyPI**: https://pypi.org/project/cookidoo-api/
- **Docs**: https://miaucl.github.io/cookidoo-api/
- Latest: v0.16.0 (Jan 2026)
- Uses email/password auth against Cookidoo backend
- Built on `aiohttp`
- Contains raw API request captures in `./docs/raw-api-requests` (intercepted from Android app)
- Currently supports: adding custom recipes to calendars and shopping lists
- **Custom recipe creation/editing is on the roadmap but not yet fully implemented**

---

### 3. `mcp-cookidoo` — MCP Server (AI → Cookidoo pipeline)

- **Repo**: https://github.com/alexandrepa/mcp-cookidoo/
- **Article**: https://medium.com/@alexandre.patelli_17989/how-i-connected-my-thermomix-to-gemini-4bd51d768abb
- Uses `cookidoo-api` under the hood
- Demonstrates generating recipes with an LLM and pushing them directly to Cookidoo
- Built with `fastmcp` framework

---

### 4. `cookidoo-scraper` (Read-only)

- **Repo**: https://github.com/tobim-dev/cookidoo-scraper
- REST API for reading recipes from Cookidoo (scraping-based)
- Useful for importing FROM Cookidoo, not uploading TO it

---

### 5. Home Assistant Integration

- **Docs**: https://www.home-assistant.io/integrations/cookidoo/
- Introduced in Home Assistant 2025.1
- Focused on shopping list sync, not recipe creation

---

### 6. AIdoo (Commercial tool)

- **Website**: https://aidoo.tools/
- AI-powered recipe converter that formats and uploads recipes to Cookidoo for TM6/TM7
- Handles text, PDF, and URL sources

---

## Mapping Our Data Model to Cookidoo

Our recipe model maps fairly directly:

| Our Field | Cookidoo Field | Notes |
|---|---|---|
| `recipe.title` | `recipeName` | Direct mapping |
| `ingredients[].name` + `quantity` + `unit` | `ingredients[].text` | Concatenate into single string |
| `steps[].instruction` | `instructions[].text` | Direct mapping |
| `recipe.prep_time_minutes` | `prepTime` | Convert to seconds (× 60) |
| `recipe.total_time_minutes` | `totalTime` | Convert to seconds (× 60) |
| `recipe.servings` | `yield.value` | Direct mapping |

---

## Key Considerations

| Concern | Detail |
|---|---|
| **No official API** | All approaches are reverse-engineered; could break at any time |
| **Auth is user-scoped** | Each user must provide their own Cookidoo JWT or credentials |
| **Recipe format** | Simple text-based ingredients/steps — maps well to our model |
| **Guided cooking** | Basic steps are supported; Thermomix-specific guided cooking params (temp, speed, time per step) may not be fully available via custom recipe endpoints |
| **Rate limiting / TOS** | Using unofficial APIs may violate Cookidoo's terms of service |
| **Locale-dependent** | API endpoints include locale (e.g. `/created-recipes/de-DE`) |

---

## Recommendation for v2 Integration

1. **Approach**: Build an Elixir HTTP client module (`Cookbook.Integrations.Cookidoo`) that implements the POST/PATCH flow from `cookiput`
2. **Auth flow**: Have users paste their JWT token from browser dev tools (simplest approach) or implement email/password auth similar to `cookidoo-api`
3. **Reference material**: The raw API request captures in `cookidoo-api`'s docs folder are the best source of truth for endpoint details
4. **Risk mitigation**: Feature-flag the integration and clearly communicate to users that it relies on unofficial APIs
5. **Consider `mcp-cookidoo`**: As a pattern reference for how an AI-to-Cookidoo pipeline can work

---

## References

- https://github.com/croeer/cookiput
- https://github.com/miaucl/cookidoo-api
- https://github.com/alexandrepa/mcp-cookidoo/
- https://github.com/tobim-dev/cookidoo-scraper
- https://www.home-assistant.io/integrations/cookidoo/
- https://aidoo.tools/
- https://cookidoo.thermomix.com/foundation/en-US/articles/learn-about-importing-recipes

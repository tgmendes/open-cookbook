defmodule CookbookWeb.RecipeImportLiveTest do
  use CookbookWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Cookbook.{Accounts, Recipes}

  setup %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")

    {:ok, recipe} =
      Recipes.create_recipe(user.id, %{
        title: "Roast broccoli",
        servings: 2,
        prep_ahead: "Chop ahead",
        freezer_friendly: true,
        freezer_notes: "Freeze a month",
        troubleshooting: "Uncover",
        variations: "Use cauliflower",
        image_credit: "Photographer",
        image_license: "Pexels License",
        image_match: :approximate,
        image_source_url: "https://pexels.com/photo/example",
        source_conversation_url: "https://claude.ai/chat/example",
        ingredients: [
          %{name: "Broccoli", ref: "broccoli", quantity_value: 250, unit: "g"},
          %{name: "Salt", ref: "salt", quantity_text: "to taste"}
        ],
        steps: [
          %{
            short_title: "Roast the veg",
            instruction: "Roast {{broccoli}}.",
            ingredient_refs: ["broccoli"]
          }
        ]
      })

    %{conn: log_in_user(conn, user), user: user, recipe: recipe}
  end

  test "cook mode renders explicit links with scaled inline quantities and advice", %{
    conn: conn,
    recipe: recipe
  } do
    {:ok, view, _} = live(conn, "/recipes/#{recipe.id}/cook")
    assert has_element?(view, "#cook-prep-ahead", "Chop ahead")
    view |> element("#more-servings") |> render_click()
    view |> element("#start-cooking") |> render_click()
    assert has_element?(view, "#step-instruction", "Roast 375 g Broccoli.")
    assert has_element?(view, "#step-ingredients", "375")
    refute has_element?(view, "#step-ingredients", "Salt")
    assert has_element?(view, "#cook-troubleshooting", "Uncover")
  end

  test "recipe detail displays structured advice and photo provenance", %{
    conn: conn,
    recipe: recipe
  } do
    {:ok, view, _} = live(conn, "/recipes/#{recipe.id}")
    assert has_element?(view, "#recipe-prep-ahead", "Chop ahead")
    assert has_element?(view, "#recipe-freezer-notes", "Freeze a month")
    assert has_element?(view, "#recipe-variations", "Use cauliflower")
    assert has_element?(view, "#image-attribution", "Photographer")
    assert has_element?(view, "#image-attribution", "Approximate")
    assert has_element?(view, "#source-conversation[href='https://claude.ai/chat/example']")
    assert has_element?(view, "#detail-steps", "Roast 250 g Broccoli.")
    view |> element("#detail-adjust") |> render_click()
    view |> form("#adjust-form", servings: "4") |> render_submit()
    assert has_element?(view, "#detail-steps", "Roast 500 g Broccoli.")
  end

  test "editing an imported recipe retains structured quantities, links and notes", %{
    conn: conn,
    user: user,
    recipe: recipe
  } do
    {:ok, view, _} = live(conn, "/recipes/#{recipe.id}/edit")
    assert has_element?(view, "#recipe-form input[name='recipe[ingredients][0][quantity_value]']")
    view |> form("#recipe-form", recipe: %{title: "Updated broccoli"}) |> render_submit()
    stored = Recipes.get_recipe!(user.id, recipe.id)
    assert stored.title == "Updated broccoli"
    assert stored.prep_ahead == "Chop ahead"
    assert stored.freezer_friendly
    assert hd(stored.steps).ingredient_refs == ["broccoli"]
    assert hd(stored.ingredients).ref == "broccoli"
    assert Decimal.equal?(hd(stored.ingredients).quantity_value, Decimal.new(250))
  end

  test "freezer-only filter excludes fresh recipes", %{conn: conn, user: user, recipe: recipe} do
    {:ok, fresh} = Recipes.create_recipe(user.id, %{title: "Fresh salad"})
    {:ok, view, _} = live(conn, "/recipes")
    view |> element("#freezer-filter") |> render_click()
    assert has_element?(view, "#recipe-#{recipe.id}")
    refute has_element?(view, "#recipe-#{fresh.id}")
  end
end

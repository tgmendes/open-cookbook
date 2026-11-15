defmodule CookbookWeb.RecipeListTest do
  use CookbookWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Cookbook.{Accounts, Recipes, Planner}

  setup %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")

    {:ok, soup} =
      Recipes.create_recipe(user.id, %{
        "user_id" => user.id,
        "title" => "Tomato soup",
        "tags" => ["Vegetarian"],
        "cook_time_minutes" => 25
      })

    {:ok, _} =
      Recipes.create_recipe(user.id, %{
        "user_id" => user.id,
        "title" => "Roast chicken",
        "tags" => ["Comfort"]
      })

    %{conn: log_in_user(conn, user), recipe: soup, user: user}
  end

  test "filter chips and search filter the real collection", %{conn: conn} do
    {:ok, view, _} = live(conn, "/recipes")
    view |> element("#recipe-filters button", "Vegetarian") |> render_click()
    assert has_element?(view, "#recipe-grid article", "Tomato soup")
    refute has_element?(view, "#recipe-grid article", "Roast chicken")
    view |> element("#recipe-filters button", "All") |> render_click()
    assert has_element?(view, "section[aria-label='All recipes'] h2", "All recipes")
    view |> form("#recipe-search", search: "Comfort") |> render_change()
    assert has_element?(view, "#recipe-grid article", "Roast chicken")
    refute has_element?(view, "#recipe-grid article", "Tomato soup")
  end

  test "adds a recipe to a chosen slot and updates its planned badge", %{
    conn: conn,
    recipe: recipe,
    user: user
  } do
    {:ok, view, _} = live(conn, "/recipes")
    view |> element("#plan-recipe-#{recipe.id}") |> render_click()

    view
    |> form("#add-to-plan-form",
      slot: %{date: Date.to_iso8601(Date.utc_today()), meal_type: "dinner"}
    )
    |> render_submit()

    assert has_element?(view, "#recipe-#{recipe.id} [data-planned]")
    assert has_element?(view, "#tonight-banner", "Tomato soup")
    {:ok, plan} = Planner.get_or_create_plan_for_week(user.id, Date.utc_today())
    assert [%{recipe_id: id, meal_type: :dinner}] = plan.entries
    assert id == recipe.id
  end

  test "empty search has a useful empty state", %{conn: conn} do
    {:ok, view, _} = live(conn, "/recipes?search=not-a-dish")
    assert has_element?(view, "#recipes-empty")
    refute has_element?(view, "#recipe-grid article")
  end
end

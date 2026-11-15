defmodule CookbookWeb.LayoutTest do
  use CookbookWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Cookbook.{Accounts, Planner, Recipes}

  setup %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")
    %{conn: log_in_user(conn, user), user: user}
  end

  test "navigation has four phone tabs and settings owns preferences", %{conn: conn} do
    {:ok, view, _} = live(conn, "/recipes")
    assert has_element?(view, "#phone-tabs a", "Today")
    assert has_element?(view, "#phone-tabs a", "Plan")
    assert has_element?(view, "#phone-tabs a", "Shop")
    refute has_element?(view, "#phone-tabs button")
    assert has_element?(view, "#desktop-settings[href='/settings']")

    {:ok, settings, _} = live(conn, "/settings")
    assert has_element?(settings, "#theme-toggle")
    settings |> element("#unit-toggle") |> render_click()
    assert has_element?(settings, "#unit-toggle", "imperial")
  end

  test "sidebar uses the user's actual dinner and shopping count", %{conn: conn, user: user} do
    {:ok, recipe} =
      Recipes.create_recipe(user.id, %{
        "user_id" => user.id,
        "title" => "Tonight's soup",
        "ingredients" => [%{"name" => "Carrots", "quantity" => "2"}],
        "steps" => [%{"instruction" => "Chop carrots"}]
      })

    {:ok, plan} = Planner.get_or_create_plan_for_week(user.id, Date.utc_today())

    {:ok, _} =
      Planner.add_entry(user.id, plan.id, %{
        day_of_week: Date.day_of_week(Date.utc_today()),
        meal_type: :dinner,
        recipe_id: recipe.id
      })

    {:ok, view, _} = live(conn, "/recipes")
    assert has_element?(view, "#up-next", "Tonight's soup")
    assert has_element?(view, "#shopping-count", "1")
    assert has_element?(view, "#up-next a[href='/recipes/#{recipe.id}/cook']")
  end

  test "settings requires authentication" do
    assert {:error, {:redirect, %{to: "/login"}}} = live(build_conn(), "/settings")
  end
end

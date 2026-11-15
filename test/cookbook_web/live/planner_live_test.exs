defmodule CookbookWeb.PlannerLiveTest do
  use CookbookWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Cookbook.{Accounts, Recipes, Planner}

  setup %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")

    {:ok, recipe} =
      Recipes.create_recipe(user.id, %{
        "user_id" => user.id,
        "title" => "Bean stew",
        "cook_time_minutes" => 45,
        "steps" => [%{"instruction" => "Simmer the beans", "duration_minutes" => 30}]
      })

    %{conn: log_in_user(conn, user), user: user, recipe: recipe}
  end

  test "calendar has lunch/dinner rows, selectable empty slots and a recipe tray", %{
    conn: conn,
    recipe: recipe
  } do
    {:ok, view, _} = live(conn, "/planner")
    assert has_element?(view, "#meal-row-lunch")
    assert has_element?(view, "#meal-row-dinner")
    assert has_element?(view, "#recipe-tray")
    view |> element("#add-1-lunch") |> render_click()
    view |> element("#tray-add-#{recipe.id}") |> render_click()
    assert has_element?(view, "#slot-1-lunch", "Bean stew")
    assert has_element?(view, "#plan-summary", "1 of 14")
    view |> element("#slot-1-lunch button[phx-click=remove_entry]") |> render_click()
    assert has_element?(view, "#add-1-lunch")
  end

  test "cook together tip only appears for a long simmer with another recipe on the same day", %{
    conn: conn,
    user: user,
    recipe: recipe
  } do
    {:ok, plan} = Planner.get_or_create_plan_for_week(user.id, Date.utc_today())

    {:ok, _} =
      Planner.add_entry(user.id, plan.id, %{
        recipe_id: recipe.id,
        day_of_week: 6,
        meal_type: :dinner
      })

    {:ok, view, _} = live(conn, "/planner")
    refute has_element?(view, "#cook-together-tip")
    {:ok, other} = Recipes.create_recipe(user.id, %{"title" => "Muffins"})

    {:ok, _} =
      Planner.add_entry(user.id, plan.id, %{
        recipe_id: other.id,
        day_of_week: 6,
        meal_type: :lunch
      })

    {:ok, view, _} = live(conn, "/planner")
    assert has_element?(view, "#cook-together-tip", "Saturday")
    assert has_element?(view, "#cook-together-tip", "Muffins")
  end

  test "week navigation updates the grid and handles invalid query dates", %{conn: conn} do
    {:ok, view, _} = live(conn, "/planner?week=oops")
    view |> element("#next-week") |> render_click()
    assert has_element?(view, "#week-calendar")
  end

  test "planner keeps manual planning without embedded AI", %{conn: conn} do
    {:ok, view, _} = live(conn, "/planner")
    assert has_element?(view, "#plan-summary", "0 of 14")
    refute has_element?(view, "#fill-slots")
    refute has_element?(view, "[phx-click=suggest_plan]")
  end
end

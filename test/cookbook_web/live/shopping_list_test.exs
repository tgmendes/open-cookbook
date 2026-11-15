defmodule CookbookWeb.ShoppingListTest do
  use CookbookWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Cookbook.{Accounts, Planner, Recipes}

  setup %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")

    {:ok, recipe} =
      Recipes.create_recipe(user.id, %{
        "user_id" => user.id,
        "title" => "Carrot soup",
        "ingredients" => [
          %{"name" => "Carrots", "quantity" => "2"},
          %{"name" => "Milk", "quantity" => "100", "unit" => "ml"}
        ]
      })

    {:ok, plan} = Planner.get_or_create_plan_for_week(user.id, Date.utc_today())

    {:ok, _} =
      Planner.add_entry(user.id, plan.id, %{
        recipe_id: recipe.id,
        day_of_week: 1,
        meal_type: :lunch
      })

    %{conn: log_in_user(conn, user)}
  end

  test "groups by aisle, shows provenance, and moves checked items to the basket", %{conn: conn} do
    {:ok, view, _} = live(conn, "/planner/shopping")
    assert has_element?(view, "#shopping-groups section", "Fruit & veg")
    assert has_element?(view, "#shopping-groups section", "Dairy & eggs")
    assert has_element?(view, "#shopping-groups button", "For Carrot soup")
    view |> element("#shopping-groups button", "carrots") |> render_click()
    assert has_element?(view, "#basket button[aria-checked=true]", "carrots")
    refute has_element?(view, "#shopping-groups button", "carrots")
    assert has_element?(view, "#shopping-count", "1")
    {:ok, reopened, _} = live(conn, "/planner/shopping")
    assert has_element?(reopened, "#basket button", "carrots")
  end

  test "adds manual extras and supports recipe grouping", %{conn: conn} do
    {:ok, view, _} = live(conn, "/planner/shopping")
    view |> form("#extra-item-form", extra: %{name: "Coffee"}) |> render_submit()
    assert has_element?(view, "#shopping-groups button", "Coffee")
    view |> element("#group-by-recipe") |> render_click()
    assert has_element?(view, "#group-by-recipe[aria-selected=true]")
    assert has_element?(view, "#shopping-groups section h2", "Carrot soup")
    {:ok, reopened, _} = live(conn, "/planner/shopping")
    assert has_element?(reopened, "#shopping-groups button", "Coffee")
  end

  test "invalid weeks fall back safely", %{conn: conn} do
    assert {:ok, view, _} = live(conn, "/planner/shopping?week=oops")
    assert has_element?(view, "#extra-item-form")
  end
end

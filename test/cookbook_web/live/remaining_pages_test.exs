defmodule CookbookWeb.RemainingPagesTest do
  use CookbookWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Cookbook.{Accounts, Recipes, Planner}

  setup %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")

    {:ok, recipe} =
      Recipes.create_recipe(user.id, %{
        "user_id" => user.id,
        "title" => "Soup",
        "servings" => 2,
        "ingredients" => [%{"name" => "Carrots", "quantity" => "2"}],
        "steps" => [%{"instruction" => "Chop carrots", "short_title" => "Chop", "position" => 0}]
      })

    %{conn: log_in_user(conn, user), user: user, recipe: recipe}
  end

  test "today shows the real dinner and recipe collection", %{
    conn: conn,
    user: user,
    recipe: recipe
  } do
    {:ok, plan} = Planner.get_or_create_plan_for_week(user.id, Date.utc_today())

    {:ok, _} =
      Planner.add_entry(user.id, plan.id, %{
        recipe_id: recipe.id,
        day_of_week: Date.day_of_week(Date.utc_today()),
        meal_type: :dinner
      })

    {:ok, view, _} = live(conn, "/")
    assert has_element?(view, "#today-dinner", "Soup")
    assert has_element?(view, "#recent-recipes a[href='/recipes/#{recipe.id}']")
  end

  test "detail offers cooking and an accessible adjustment form", %{conn: conn, recipe: recipe} do
    {:ok, view, _} = live(conn, "/recipes/#{recipe.id}")
    assert has_element?(view, "#recipe-detail h1", "Soup")
    assert has_element?(view, "#detail-cook[href='/recipes/#{recipe.id}/cook']")
    view |> element("#detail-adjust") |> render_click()
    view |> form("#adjust-form", servings: "0") |> render_submit()
    assert has_element?(view, "#adjust-error")
  end

  test "manual creation works on the shared responsive form", %{conn: conn} do
    {:ok, view, _} = live(conn, "/recipes/new")
    assert has_element?(view, "#recipe-form")
    view |> element("#add-ingredient") |> render_click()
    view |> element("#add-step") |> render_click()

    view
    |> form("#recipe-form",
      recipe: %{
        title: "Toast",
        ingredients: %{"0" => %{name: "Bread", quantity_value: "1"}},
        steps: %{"0" => %{instruction: "Toast the bread", short_title: "Toast"}}
      }
    )
    |> render_submit()

    assert_redirect(view)
  end

  test "editing and adding steps preserves existing short titles", %{conn: conn, recipe: recipe} do
    {:ok, view, _} = live(conn, "/recipes/#{recipe.id}/edit")
    view |> element("#add-step") |> render_click()
    assert has_element?(view, "input[name='recipe[steps][0][short_title]'][value='Chop']")
    assert has_element?(view, "textarea[name='recipe[steps][1][instruction]']")
  end

  test "old creator links open the manual form without embedded AI", %{conn: conn} do
    {:ok, view, _} = live(conn, "/recipes/new?mode=url")
    assert has_element?(view, "#recipe-form")
    refute has_element?(view, "#creator-form")
  end

  test "login sends a magic link and doesn't expose account membership" do
    {:ok, view, _} = live(build_conn(), "/login")
    view |> form("#login_form", login: %{email: "test@example.com"}) |> render_submit()
    assert has_element?(view, "#login-sent")
    assert_receive {:email, %Swoosh.Email{to: [{_, "test@example.com"}]}}
    {:ok, other, _} = live(build_conn(), "/login")
    other |> form("#login_form", login: %{email: "unknown@example.com"}) |> render_submit()
    assert has_element?(other, "#login-sent")
  end
end

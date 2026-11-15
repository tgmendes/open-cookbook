defmodule CookbookWeb.CookbookLiveTest do
  use CookbookWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Cookbook.{Accounts, Recipes}

  setup %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")

    conn =
      init_test_session(conn, %{user_id: user.id, authenticated_at: System.system_time(:second)})

    %{conn: conn, user: user}
  end

  test "new recipes open a manual form and save nested content", %{conn: conn, user: user} do
    {:ok, view, _} = live(conn, "/recipes/new")
    assert has_element?(view, "#recipe-form")
    refute has_element?(view, "[phx-submit=ai_submit]")
    view |> element("#add-ingredient") |> render_click()
    view |> element("#add-step") |> render_click()

    view
    |> form("#recipe-form",
      recipe: %{
        title: "Manual pasta",
        servings: "2",
        tags_input: "quick, pasta",
        ingredients: %{"0" => %{name: "Pasta", quantity_value: "200", unit: "g"}},
        steps: %{"0" => %{instruction: "Boil water", duration_minutes: "10"}}
      }
    )
    |> render_submit()

    [recipe] = Recipes.list_recipes(user.id)
    assert_redirect(view, "/recipes/#{recipe.id}")

    assert {:ok,
            %{
              ingredients: [%{name: "Pasta"}],
              steps: [%{instruction: "Boil water"}],
              tags: ["quick", "pasta"]
            }} = Recipes.get_recipe(user.id, recipe.id)
  end

  test "editing preserves nested content and updates the title", %{conn: conn, user: user} do
    {:ok, recipe} =
      Recipes.create_recipe(user.id, %{
        "title" => "Original",
        "ingredients" => [%{"name" => "Pasta"}],
        "steps" => [%{"instruction" => "Boil"}]
      })

    {:ok, view, _} = live(conn, "/recipes/#{recipe.id}/edit")
    view |> form("#recipe-form", recipe: %{title: "Updated"}) |> render_submit()

    assert {:ok, %{title: "Updated", ingredients: [_], steps: [_]}} =
             Recipes.get_recipe(user.id, recipe.id)
  end

  test "removing an ingredient and then adding another preserves the remaining rows", %{
    conn: conn,
    user: user
  } do
    {:ok, recipe} =
      Recipes.create_recipe(user.id, %{
        "title" => "Salad",
        "ingredients" => [
          %{"name" => "Tomato", "position" => 0},
          %{"name" => "Lettuce", "position" => 1}
        ]
      })

    {:ok, view, _} = live(conn, "/recipes/#{recipe.id}/edit")
    view |> element("#remove-ingredient-0") |> render_click()
    view |> element("#add-ingredient") |> render_click()

    view
    |> form("#recipe-form",
      recipe: %{ingredients: %{"0" => %{name: "Lettuce"}, "1" => %{name: "Oil"}}}
    )
    |> render_submit()

    assert {:ok, %{ingredients: ingredients}} = Recipes.get_recipe(user.id, recipe.id)
    assert Enum.map(ingredients, & &1.name) == ["Lettuce", "Oil"]
  end

  test "dashboard, catalog, weekly planner, shopping list and walkthrough remain available", %{
    conn: conn,
    user: user
  } do
    {:ok, recipe} =
      Recipes.create_recipe(user.id, %{
        "title" => "Pasta",
        "steps" => [%{"instruction" => "Boil water"}, %{"instruction" => "Serve"}]
      })

    for path <- ["/", "/recipes", "/planner", "/planner/shopping", "/recipes/#{recipe.id}"] do
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "#cookbook-content")
      refute has_element?(view, "[phx-click=suggest_plan]")
      refute has_element?(view, "a[href*='mode=ai']")
    end

    {:ok, view, _} = live(conn, "/recipes/#{recipe.id}/cook")
    assert has_element?(view, "#cook-prep")
    view |> element("#start-cooking") |> render_click()
    view |> element("#next-step") |> render_click()
    assert has_element?(view, "#cook-step", "Serve")
  end

  test "foreign recipes cannot be opened or deleted through LiveView", %{conn: conn} do
    other =
      %Accounts.User{}
      |> Accounts.User.changeset(%{email: "other@example.com"})
      |> Cookbook.Repo.insert!()

    {:ok, recipe} = Recipes.create_recipe(other.id, %{"title" => "Private"})

    for suffix <- ["", "/edit", "/cook"] do
      assert_raise Ecto.NoResultsError, fn -> live(conn, "/recipes/#{recipe.id}#{suffix}") end
    end

    {:ok, view, _} = live(conn, "/recipes")
    render_hook(view, "delete", %{id: recipe.id})
    assert {:ok, _} = Recipes.get_recipe(other.id, recipe.id)
  end

  test "a live connection loses write access when its owner is removed", %{conn: conn, user: user} do
    {:ok, view, _} = live(conn, "/recipes/new")
    user |> Ecto.Changeset.change(email: "removed@example.com") |> Cookbook.Repo.update!()
    view |> form("#recipe-form", recipe: %{title: "Denied"}) |> render_submit()
    assert_redirect(view, "/login")
    assert [] == Recipes.list_recipes(user.id)
  end

  test "a recipe deleted while its editor is open redirects instead of crashing", %{
    conn: conn,
    user: user
  } do
    {:ok, recipe} = Recipes.create_recipe(user.id, %{"title" => "Temporary"})
    {:ok, view, _} = live(conn, "/recipes/#{recipe.id}/edit")
    {:ok, _} = Recipes.delete_recipe(user.id, recipe.id)
    view |> form("#recipe-form", recipe: %{title: "Too late"}) |> render_submit()
    assert_redirect(view, "/recipes")
  end
end

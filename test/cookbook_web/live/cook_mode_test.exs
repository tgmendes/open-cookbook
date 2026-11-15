defmodule CookbookWeb.CookModeTest do
  use CookbookWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Cookbook.{Accounts, Recipes}

  setup %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")

    {:ok, recipe} =
      Recipes.create_recipe(user.id, %{
        "user_id" => user.id,
        "title" => "Carrot soup",
        "servings" => 2,
        "ingredients" => [%{"name" => "Carrots", "quantity" => "2"}],
        "steps" => [
          %{
            "instruction" => "Chop the carrots into small pieces",
            "short_title" => "Chop carrots",
            "position" => 0
          },
          %{
            "instruction" => "Simmer the carrots until tender",
            "position" => 1,
            "duration_minutes" => 10
          }
        ]
      })

    %{conn: log_in_user(conn, user), user: user, recipe: recipe}
  end

  test "opens prep, gathers ingredients and starts steps with short titles", %{
    conn: conn,
    recipe: recipe
  } do
    {:ok, view, _} = live(conn, "/recipes/#{recipe.id}/cook")
    assert has_element?(view, "#cook-prep")
    refute has_element?(view, "[data-theme]")
    view |> element("#gather-0") |> render_click()
    assert has_element?(view, "#gather-0[aria-checked=true]")
    view |> element("#start-cooking") |> render_click()
    assert has_element?(view, "#step-heading", "Chop carrots")
    view |> element("#next-step") |> render_click()
    assert has_element?(view, "#step-heading", "Simmer the carrots until tender")
    assert has_element?(view, "#start-timer")
    assert has_element?(view, "#cook-timers[phx-update=ignore]")
    view |> element("#next-step") |> render_click()
    assert has_element?(view, "#cook-finished")
  end

  test "keyboard navigation is bounded and prep is reachable", %{conn: conn, recipe: recipe} do
    {:ok, view, _} = live(conn, "/recipes/#{recipe.id}/cook")
    render_hook(view, "keydown", %{"key" => "ArrowRight"})
    assert has_element?(view, "#cook-step[data-step='0']")
    render_hook(view, "keydown", %{"key" => "ArrowLeft"})
    assert has_element?(view, "#cook-prep")
  end

  test "servings adjustment scales quantities locally", %{
    conn: conn,
    recipe: recipe
  } do
    {:ok, view, _} = live(conn, "/recipes/#{recipe.id}/cook")
    view |> element("#more-servings") |> render_click()
    refute has_element?(view, "#adjust-error")
    assert has_element?(view, "#servings", "3")
    assert has_element?(view, "#gather-0", "3")
    refute has_element?(view, "#more-servings[disabled]")
  end

  test "short titles survive persistence", %{recipe: recipe, user: user} do
    assert hd(Recipes.get_recipe!(user.id, recipe.id).steps).short_title == "Chop carrots"
  end

  test "prep derives equipment from the instructions without inventing it", %{
    conn: conn,
    user: user,
    recipe: recipe
  } do
    first = hd(recipe.steps)

    {:ok, _} =
      Recipes.update_recipe(user.id, recipe.id, %{
        "steps" => [
          %{
            "id" => first.id,
            "instruction" => "Chop carrots on a chopping board and add to a saucepan."
          }
        ]
      })

    {:ok, view, _} = live(conn, "/recipes/#{recipe.id}/cook")
    assert has_element?(view, "#cook-equipment", "Chopping board")
    assert has_element?(view, "#cook-equipment", "Saucepan")
    refute has_element?(view, "#cook-equipment", "Baking tray")
  end
end

defmodule CookbookWeb.CookModeTest do
  use CookbookWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Cookbook.{Accounts, Recipes}

  setup %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")

    {:ok, recipe} =
      Recipes.create_recipe(%{
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

    %{conn: init_test_session(conn, %{user_id: user.id}), recipe: recipe}
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

  test "servings adjustment uses existing AI flow and recovers from failure", %{
    conn: conn,
    recipe: recipe
  } do
    {:ok, view, _} = live(conn, "/recipes/#{recipe.id}/cook")
    view |> element("#more-servings") |> render_click()
    render_async(view)
    assert has_element?(view, "#adjust-error")
    assert has_element?(view, "#servings", "2")
    refute has_element?(view, "#more-servings[disabled]")
  end

  test "short titles survive persistence", %{recipe: recipe} do
    assert hd(Recipes.get_recipe!(recipe.id).steps).short_title == "Chop carrots"
  end

  test "prep derives equipment from the instructions without inventing it", %{
    conn: conn,
    recipe: recipe
  } do
    first = hd(recipe.steps)

    {:ok, _} =
      Recipes.update_recipe(recipe, %{
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

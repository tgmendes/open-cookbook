defmodule CookbookWeb.CookbookApiController do
  use CookbookWeb, :controller
  alias Cookbook.{Recipes, Planner, ApiRequests}
  alias CookbookWeb.{ApiInput, CookbookJSON}
  action_fallback CookbookWeb.ApiFallbackController

  def profile(conn, _params) do
    json(conn, %{
      data: %{
        unit_system: conn.assigns.current_user.unit_system,
        ingredient_units:
          Cookbook.Recipes.Ingredient.units_for_system(conn.assigns.current_user.unit_system)
      }
    })
  end

  def index(conn, params) do
    with {:ok, opts} <- ApiInput.pagination(params) do
      limit = opts[:limit]

      recipes =
        Recipes.list_recipes(conn.assigns.current_user.id, Keyword.put(opts, :limit, limit + 1))

      json(conn, %{
        data: recipes |> Enum.take(limit) |> Enum.map(&CookbookJSON.summary/1),
        meta: %{limit: limit, offset: opts[:offset], has_more: length(recipes) > limit}
      })
    end
  end

  def create(conn, _params) do
    with [key] when byte_size(key) in 1..128 <- get_req_header(conn, "idempotency-key"),
         {:ok, attrs} <- ApiInput.recipe(conn.body_params),
         {:ok, result} <-
           ApiRequests.run(conn.assigns.current_user.id, key, attrs, fn ->
             with {:ok, recipe} <- Recipes.create_recipe(conn.assigns.current_user.id, attrs),
                  {:ok, recipe} <- Recipes.get_recipe(conn.assigns.current_user.id, recipe.id) do
               {:ok, %{data: CookbookJSON.recipe(recipe)}}
             end
           end) do
      conn |> put_status(:created) |> json(result)
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_input}
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, recipe} <- Recipes.get_recipe(conn.assigns.current_user.id, id) do
      json(conn, %{data: CookbookJSON.recipe(recipe)})
    end
  end

  def update(conn, %{"id" => id}) do
    with {:ok, _} <- Recipes.get_recipe(conn.assigns.current_user.id, id),
         {:ok, attrs} <- ApiInput.recipe(conn.body_params),
         {:ok, recipe} <- Recipes.update_recipe(conn.assigns.current_user.id, id, attrs) do
      json(conn, %{data: CookbookJSON.recipe(recipe)})
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, _} <- Recipes.delete_recipe(conn.assigns.current_user.id, id),
         do: send_resp(conn, :no_content, "")
  end

  def upload_image(conn, %{"id" => id}) do
    with {:ok, recipe} <- Recipes.get_recipe(conn.assigns.current_user.id, id),
         {:ok, attrs} <- Cookbook.RecipeImages.upload(recipe, conn.body_params),
         {:ok, recipe} <- Recipes.update_recipe(conn.assigns.current_user.id, id, attrs) do
      json(conn, %{data: CookbookJSON.recipe(recipe)})
    end
  end

  def plan(conn, %{"week" => week}) do
    with {:ok, date} <- ApiInput.date(week) do
      json(conn, %{
        data: CookbookJSON.plan(Planner.get_plan_for_week(conn.assigns.current_user.id, date))
      })
    end
  end

  def replace_slot(conn, params) do
    with {:ok, date} <- ApiInput.date(params["week"]),
         {:ok, day, meal, ids} <- ApiInput.slot(params, conn.body_params),
         {:ok, plan} <- Planner.replace_slot(conn.assigns.current_user.id, date, day, meal, ids) do
      json(conn, %{data: CookbookJSON.plan(plan)})
    end
  end

  def shopping(conn, %{"week" => week}) do
    with {:ok, date} <- ApiInput.date(week) do
      items =
        Planner.shopping_list_for_week(conn.assigns.current_user.id, date)
        |> Enum.map(&Map.take(&1, [:name, :quantity, :unit]))

      json(conn, %{data: %{week_start: Planner.normalize_to_monday(date), items: items}})
    end
  end
end

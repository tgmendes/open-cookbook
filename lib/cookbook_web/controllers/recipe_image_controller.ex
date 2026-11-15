defmodule CookbookWeb.RecipeImageController do
  use CookbookWeb, :controller
  action_fallback CookbookWeb.ApiFallbackController

  def show(conn, %{"id" => id, "filename" => filename}) do
    with {:ok, recipe} <- Cookbook.Recipes.get_recipe(conn.assigns.current_user.id, id),
         {:ok, bytes, type} <- Cookbook.RecipeImages.read(recipe, filename) do
      conn
      |> put_resp_header("content-type", type)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> send_resp(:ok, bytes)
    end
  end
end

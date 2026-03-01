defmodule Cookbook.Recipes do
  @moduledoc """
  The Recipes context. Manages recipes with ingredients and steps.
  """

  import Ecto.Query
  alias Cookbook.Repo
  alias Cookbook.Recipes.Recipe

  @doc """
  Lists recipes for a user with optional search and tag filtering.
  """
  def list_recipes(user_id, opts \\ []) do
    search = Keyword.get(opts, :search)
    tag = Keyword.get(opts, :tag)

    Recipe
    |> where(user_id: ^user_id)
    |> maybe_search(search)
    |> maybe_filter_tag(tag)
    |> order_by([r], desc: r.updated_at)
    |> Repo.all()
  end

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    search_term = "%#{search}%"

    from r in query,
      where: ilike(r.title, ^search_term) or
             fragment("EXISTS (SELECT 1 FROM ingredients i WHERE i.recipe_id = ? AND i.name ILIKE ?)", r.id, ^search_term)
  end

  defp maybe_filter_tag(query, nil), do: query
  defp maybe_filter_tag(query, ""), do: query

  defp maybe_filter_tag(query, tag) do
    from r in query, where: ^tag in r.tags
  end

  @doc """
  Gets a single recipe with preloaded ingredients and steps.
  Raises `Ecto.NoResultsError` if the Recipe does not exist.
  """
  def get_recipe!(id) do
    Recipe
    |> Repo.get!(id)
    |> Repo.preload([:ingredients, :steps])
  end

  @doc """
  Creates a recipe with nested ingredients and steps.
  """
  def create_recipe(attrs) do
    %Recipe{}
    |> Recipe.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a recipe with nested ingredients and steps.
  """
  def update_recipe(%Recipe{} = recipe, attrs) do
    recipe
    |> Repo.preload([:ingredients, :steps])
    |> Recipe.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a recipe.
  """
  def delete_recipe(%Recipe{} = recipe) do
    Repo.delete(recipe)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking recipe changes.
  """
  def change_recipe(%Recipe{} = recipe, attrs \\ %{}) do
    recipe
    |> Repo.preload([:ingredients, :steps])
    |> Recipe.changeset(attrs)
  end

  @doc """
  Returns all unique tags used by a user's recipes.
  """
  def list_tags(user_id) do
    from(r in Recipe,
      where: r.user_id == ^user_id,
      select: r.tags
    )
    |> Repo.all()
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end
end

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
    |> order_by([r], asc: r.id)
    |> maybe_paginate(opts)
    |> Repo.all()
  end

  defp maybe_paginate(query, opts) do
    case Keyword.get(opts, :limit) do
      nil -> query
      count -> query |> limit(^count) |> offset(^Keyword.get(opts, :offset, 0))
    end
  end

  def get_recipe(user_id, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Recipe{} = recipe <- Repo.get_by(Recipe, id: id, user_id: user_id) do
      {:ok, Repo.preload(recipe, [:ingredients, :steps])}
    else
      _ -> {:error, :not_found}
    end
  end

  def get_recipe!(user_id, id) do
    case get_recipe(user_id, id) do
      {:ok, recipe} -> recipe
      {:error, :not_found} -> raise Ecto.NoResultsError, queryable: Recipe
    end
  end

  def create_recipe(user_id, attrs) do
    %Recipe{user_id: user_id}
    |> Recipe.changeset(attrs)
    |> Repo.insert()
  end

  def update_recipe(user_id, id, attrs) do
    with {:ok, recipe} <- get_recipe(user_id, id) do
      recipe |> Recipe.changeset(attrs) |> Repo.update()
    end
  end

  def delete_recipe(user_id, id) do
    with {:ok, recipe} <- get_recipe(user_id, id), do: Repo.delete(recipe)
  end

  defp maybe_search(query, nil), do: query
  defp maybe_search(query, ""), do: query

  defp maybe_search(query, search) do
    search_term = "%#{search}%"

    from r in query,
      where:
        ilike(r.title, ^search_term) or
          fragment(
            "EXISTS (SELECT 1 FROM ingredients i WHERE i.recipe_id = ? AND i.name ILIKE ?)",
            r.id,
            ^search_term
          )
  end

  defp maybe_filter_tag(query, nil), do: query
  defp maybe_filter_tag(query, ""), do: query

  defp maybe_filter_tag(query, tag) do
    from r in query, where: ^tag in r.tags
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

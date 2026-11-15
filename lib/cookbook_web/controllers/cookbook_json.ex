defmodule CookbookWeb.CookbookJSON do
  @moduledoc false
  @recipe_fields [
    :id,
    :title,
    :description,
    :servings,
    :prep_time_minutes,
    :cook_time_minutes,
    :total_time_minutes,
    :source_url,
    :source_type,
    :tags,
    :image_url,
    :notes,
    :inserted_at,
    :updated_at
  ]

  def recipe(recipe) do
    recipe
    |> summary()
    |> Map.put(
      :ingredients,
      Enum.map(
        recipe.ingredients,
        &Map.take(&1, [:name, :quantity, :unit, :group_name, :position])
      )
    )
    |> Map.put(
      :steps,
      Enum.map(
        recipe.steps,
        &Map.take(&1, [:instruction, :short_title, :position, :duration_minutes])
      )
    )
  end

  def summary(recipe), do: Map.take(recipe, @recipe_fields)

  def plan(plan) do
    %{
      week_start: plan.week_start,
      entries:
        plan.entries
        |> Enum.sort_by(&{&1.day_of_week, &1.meal_type, &1.position})
        |> Enum.map(fn entry ->
          %{
            id: entry.id,
            day_of_week: entry.day_of_week,
            meal_type: entry.meal_type,
            position: entry.position,
            recipe_id: entry.recipe_id,
            recipe_title: entry.recipe.title
          }
        end)
    }
  end
end

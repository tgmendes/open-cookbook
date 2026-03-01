defmodule Cookbook.Planner.MealPlanEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "meal_plan_entries" do
    field :day_of_week, :integer
    field :meal_type, Ecto.Enum, values: [:lunch, :dinner]
    field :position, :integer, default: 0

    belongs_to :meal_plan, Cookbook.Planner.MealPlan
    belongs_to :recipe, Cookbook.Recipes.Recipe
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:day_of_week, :meal_type, :position, :meal_plan_id, :recipe_id])
    |> validate_required([:day_of_week, :meal_type, :meal_plan_id, :recipe_id])
    |> validate_inclusion(:day_of_week, 1..7)
    |> unique_constraint([:meal_plan_id, :day_of_week, :meal_type, :position])
    |> foreign_key_constraint(:meal_plan_id)
    |> foreign_key_constraint(:recipe_id)
  end
end

defmodule Cookbook.Recipes.Step do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "steps" do
    field :instruction, :string
    field :short_title, :string
    field :position, :integer, default: 0
    field :duration_minutes, :integer
    field :ingredient_refs, {:array, :string}, default: []

    belongs_to :recipe, Cookbook.Recipes.Recipe
  end

  def changeset(step, attrs) do
    step
    |> cast(attrs, [:instruction, :short_title, :position, :duration_minutes, :ingredient_refs])
    |> validate_required([:instruction])
    |> validate_length(:short_title, max: 200)
    |> validate_number(:duration_minutes, greater_than_or_equal_to: 0)
    |> validate_length(:ingredient_refs, max: 200)
  end

  def instruction(step, ingredients) do
    by_ref = Map.new(ingredients, &{&1.ref, &1})

    Regex.replace(~r/\{\{([a-zA-Z0-9_-]+)\}\}/, step.instruction, fn token, ref ->
      case Map.get(by_ref, ref) do
        nil ->
          token

        ingredient ->
          Enum.reject([ingredient.quantity, ingredient.unit, ingredient.name], &(&1 in [nil, ""]))
          |> Enum.join(" ")
      end
    end)
  end

  def title(step) do
    case step.short_title do
      title when is_binary(title) and title != "" -> title
      _ -> step.instruction |> String.split() |> Enum.take(6) |> Enum.join(" ")
    end
  end
end

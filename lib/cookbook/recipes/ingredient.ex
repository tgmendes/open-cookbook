defmodule Cookbook.Recipes.Ingredient do
  use Ecto.Schema
  import Ecto.Changeset

  @metric_units ["g", "kg", "ml", "l"]
  @imperial_units ["cup", "tbsp", "tsp", "oz", "lb"]
  @universal_units ["", "piece", "clove", "slice", "bunch", "pinch", "sprig", "can", "strip", "handful"]

  @units @universal_units ++ @metric_units ++ @imperial_units

  def units, do: @units

  def units_for_system("metric"), do: @metric_units ++ @universal_units
  def units_for_system("imperial"), do: @imperial_units ++ @universal_units
  def units_for_system(_), do: @units

  def unit_options do
    Enum.map(@units, fn
      "" -> {"—", ""}
      u -> {u, u}
    end)
  end

  def unit_options(system) do
    system
    |> units_for_system()
    |> Enum.map(fn
      "" -> {"—", ""}
      u -> {u, u}
    end)
  end

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "ingredients" do
    field :name, :string
    field :quantity, :string
    field :unit, :string
    field :group_name, :string
    field :position, :integer, default: 0

    belongs_to :recipe, Cookbook.Recipes.Recipe
  end

  def changeset(ingredient, attrs) do
    ingredient
    |> cast(attrs, [:name, :quantity, :unit, :group_name, :position])
    |> validate_required([:name])
  end
end

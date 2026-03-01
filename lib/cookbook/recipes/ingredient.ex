defmodule Cookbook.Recipes.Ingredient do
  use Ecto.Schema
  import Ecto.Changeset

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

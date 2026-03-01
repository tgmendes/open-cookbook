defmodule Cookbook.Recipes.Step do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "steps" do
    field :instruction, :string
    field :position, :integer, default: 0
    field :duration_minutes, :integer

    belongs_to :recipe, Cookbook.Recipes.Recipe
  end

  def changeset(step, attrs) do
    step
    |> cast(attrs, [:instruction, :position, :duration_minutes])
    |> validate_required([:instruction])
  end
end

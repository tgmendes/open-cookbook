defmodule Cookbook.Planner.MealPlan do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "meal_plans" do
    field :week_start, :date
    field :notes, :string
    field :shopping_checked, {:array, :string}, default: []
    field :shopping_extras, {:array, :string}, default: []

    belongs_to :user, Cookbook.Accounts.User
    has_many :entries, Cookbook.Planner.MealPlanEntry, on_delete: :delete_all

    timestamps(type: :utc_datetime)
  end

  def changeset(meal_plan, attrs) do
    meal_plan
    |> cast(attrs, [:week_start, :notes])
    |> validate_required([:week_start, :user_id])
    |> unique_constraint([:user_id, :week_start])
  end
end

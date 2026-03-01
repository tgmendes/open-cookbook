defmodule Cookbook.Recipes.Recipe do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "recipes" do
    field :title, :string
    field :description, :string
    field :servings, :integer
    field :prep_time_minutes, :integer
    field :cook_time_minutes, :integer
    field :total_time_minutes, :integer
    field :source_url, :string
    field :source_type, Ecto.Enum, values: [:manual, :scraped, :generated], default: :manual
    field :tags, {:array, :string}, default: []
    field :image_url, :string
    field :notes, :string

    belongs_to :user, Cookbook.Accounts.User
    has_many :ingredients, Cookbook.Recipes.Ingredient, on_replace: :delete, preload_order: [asc: :position]
    has_many :steps, Cookbook.Recipes.Step, on_replace: :delete, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  def changeset(recipe, attrs) do
    recipe
    |> cast(attrs, [
      :title, :description, :servings, :prep_time_minutes, :cook_time_minutes,
      :source_url, :source_type, :tags, :image_url, :notes, :user_id
    ])
    |> validate_required([:title, :user_id])
    |> compute_total_time()
    |> cast_assoc(:ingredients, with: &Cookbook.Recipes.Ingredient.changeset/2, sort_param: :ingredients_sort, drop_param: :ingredients_drop)
    |> cast_assoc(:steps, with: &Cookbook.Recipes.Step.changeset/2, sort_param: :steps_sort, drop_param: :steps_drop)
    |> foreign_key_constraint(:user_id)
  end

  defp compute_total_time(changeset) do
    prep = get_field(changeset, :prep_time_minutes)
    cook = get_field(changeset, :cook_time_minutes)

    total =
      case {prep, cook} do
        {nil, nil} -> nil
        {p, nil} -> p
        {nil, c} -> c
        {p, c} -> p + c
      end

    put_change(changeset, :total_time_minutes, total)
  end
end

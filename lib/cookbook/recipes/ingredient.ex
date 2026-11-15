defmodule Cookbook.Recipes.Ingredient do
  use Ecto.Schema
  import Ecto.Changeset

  @metric_units ["g", "kg", "ml", "l"]
  @imperial_units ["cup", "tbsp", "tsp", "oz", "lb"]
  @universal_units [
    "",
    "piece",
    "clove",
    "slice",
    "bunch",
    "pinch",
    "sprig",
    "can",
    "strip",
    "handful"
  ]

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
    field :quantity_value, :decimal
    field :quantity_text, :string
    field :ref, :string
    field :unit, :string
    field :group_name, :string
    field :position, :integer, default: 0

    belongs_to :recipe, Cookbook.Recipes.Recipe
  end

  def changeset(ingredient, attrs) do
    ingredient
    |> cast(attrs, [
      :name,
      :quantity,
      :quantity_value,
      :quantity_text,
      :ref,
      :unit,
      :group_name,
      :position
    ])
    |> validate_required([:name])
    |> validate_length(:name, max: 255)
    |> validate_length(:unit, max: 255)
    |> validate_length(:group_name, max: 255)
    |> validate_format(:ref, ~r/^[a-zA-Z0-9_-]{1,100}$/)
    |> normalize_quantity(attrs)
    |> validate_number(:quantity_value,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1_000_000_000
    )
    |> validate_length(:quantity, max: 255)
    |> validate_length(:quantity_text, max: 255)
    |> ensure_ref()
    |> unique_constraint([:recipe_id, :ref])
    |> check_constraint(:quantity_value, name: :quantity_value_nonnegative)
  end

  defp ensure_ref(changeset) do
    if get_field(changeset, :ref),
      do: changeset,
      else: put_change(changeset, :ref, Ecto.UUID.generate())
  end

  defp normalize_quantity(changeset, attrs) do
    legacy? = Map.has_key?(attrs, "quantity") or Map.has_key?(attrs, :quantity)

    structured? =
      Enum.any?(
        ["quantity_value", :quantity_value, "quantity_text", :quantity_text],
        &Map.has_key?(attrs, &1)
      )

    changeset =
      if legacy? and not structured? do
        text = get_field(changeset, :quantity)

        changeset
        |> put_change(:quantity_text, text)
        |> put_change(:quantity_value, Cookbook.Recipes.Quantity.parse(text))
      else
        changeset
      end

    value = get_field(changeset, :quantity_value)
    text = get_field(changeset, :quantity_text)
    display = if value, do: text || Cookbook.Recipes.Quantity.format(value), else: text
    put_change(changeset, :quantity, display)
  end
end

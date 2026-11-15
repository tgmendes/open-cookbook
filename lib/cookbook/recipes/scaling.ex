defmodule Cookbook.Recipes.Scaling do
  @moduledoc "Local decimal serving adjustment. Non-numeric quantities remain unchanged."
  alias Cookbook.Recipes.Quantity

  def scale(%{servings: original, ingredients: ingredients}, target)
      when is_integer(original) and original > 0 and is_integer(target) and target > 0 do
    {:ok,
     %{
       servings: target,
       ingredients: Enum.map(ingredients, &scale_ingredient(&1, original, target))
     }}
  end

  def scale(_, _), do: {:error, :invalid_servings}

  defp scale_ingredient(ingredient, original, target) do
    value = Map.get(ingredient, :quantity_value) || Quantity.parse(ingredient.quantity)

    if value do
      value = value |> Decimal.mult(Decimal.new(target)) |> Decimal.div(Decimal.new(original))
      ingredient = %{ingredient | quantity: Quantity.format(value)}

      if Map.has_key?(ingredient, :quantity_value),
        do: %{ingredient | quantity_value: value, quantity_text: nil},
        else: ingredient
    else
      ingredient
    end
  end
end

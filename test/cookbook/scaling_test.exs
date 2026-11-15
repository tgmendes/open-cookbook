defmodule Cookbook.ScalingTest do
  use ExUnit.Case, async: true
  alias Cookbook.Recipes.{Recipe, Ingredient, Scaling}

  test "scales numeric and fractional quantities without an AI service" do
    recipe = %Recipe{
      servings: 2,
      ingredients: Enum.map(["200", "1/2", "1 1/2", "to taste", nil], &%Ingredient{quantity: &1})
    }

    assert {:ok, %{servings: 4, ingredients: ingredients}} = Scaling.scale(recipe, 4)
    assert Enum.map(ingredients, & &1.quantity) == ["400", "1", "3", "to taste", nil]
    assert Enum.at(recipe.ingredients, 0).quantity == "200"
  end

  test "requires a positive original and target serving count" do
    for {original, target} <- [{nil, 2}, {0, 2}, {2, 0}, {2, -1}, {2, "4"}] do
      assert {:error, :invalid_servings} = Scaling.scale(%Recipe{servings: original}, target)
    end
  end
end

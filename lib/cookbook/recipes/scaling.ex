defmodule Cookbook.Recipes.Scaling do
  @moduledoc "Local serving adjustment. Non-numeric quantities are preserved verbatim."

  def scale(%{servings: original, ingredients: ingredients}, target)
      when is_integer(original) and original > 0 and is_integer(target) and target > 0 do
    {:ok,
     %{
       servings: target,
       ingredients:
         Enum.map(ingredients, fn ingredient ->
           %{ingredient | quantity: scale_quantity(ingredient.quantity, target / original)}
         end)
     }}
  end

  def scale(_, _), do: {:error, :invalid_servings}

  defp scale_quantity(value, factor) when is_binary(value) do
    case number(String.trim(value)) do
      {:ok, number} -> (number * factor) |> Float.round(3) |> format()
      :error -> value
    end
  end

  defp scale_quantity(value, _), do: value

  defp number(value) do
    cond do
      Regex.match?(~r/^\d+\s+\d+\/\d+$/, value) ->
        [whole, fraction] = String.split(value, ~r/\s+/, parts: 2)

        case number(fraction) do
          {:ok, part} -> {:ok, String.to_integer(whole) + part}
          _ -> :error
        end

      Regex.match?(~r/^\d+\/\d+$/, value) ->
        [top, bottom] = value |> String.split("/") |> Enum.map(&String.to_integer/1)
        if bottom > 0, do: {:ok, top / bottom}, else: :error

      true ->
        case Float.parse(value) do
          {number, ""} when number >= 0 -> {:ok, number}
          _ -> :error
        end
    end
  end

  defp format(number) when number == trunc(number), do: Integer.to_string(trunc(number))

  defp format(number),
    do:
      :erlang.float_to_binary(number, [:compact, decimals: 3])
      |> String.trim_trailing("0")
      |> String.trim_trailing(".")
end

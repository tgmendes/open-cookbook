defmodule Cookbook.Recipes.Quantity do
  @moduledoc "Decimal quantities with a lossless text fallback for legacy recipes."

  def parse(nil), do: nil

  def parse(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      Regex.match?(~r/^\d+\s+\d+\/\d+$/, value) ->
        [whole, fraction] = String.split(value, ~r/\s+/, parts: 2)

        case parse(fraction) do
          nil -> nil
          part -> Decimal.add(Decimal.new(whole), part)
        end

      Regex.match?(~r/^\d+\/\d+$/, value) ->
        [top, bottom] = String.split(value, "/")

        if Decimal.equal?(Decimal.new(bottom), 0),
          do: nil,
          else: Decimal.div(Decimal.new(top), Decimal.new(bottom))

      Regex.match?(~r/^\d+(\.\d+)?$/, value) ->
        Decimal.new(value)

      true ->
        nil
    end
  end

  def format(value),
    do: value |> Decimal.round(6) |> Decimal.normalize() |> Decimal.to_string(:normal)
end

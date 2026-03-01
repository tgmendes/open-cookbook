defmodule Cookbook.Planner do
  @moduledoc """
  The Planner context. Manages weekly meal plans.
  """

  import Ecto.Query
  alias Cookbook.Repo
  alias Cookbook.Planner.{MealPlan, MealPlanEntry}

  @day_names %{
    1 => "Monday",
    2 => "Tuesday",
    3 => "Wednesday",
    4 => "Thursday",
    5 => "Friday",
    6 => "Saturday",
    7 => "Sunday"
  }

  def day_name(day_of_week), do: Map.get(@day_names, day_of_week, "")

  @short_day_names %{
    1 => "Mon",
    2 => "Tue",
    3 => "Wed",
    4 => "Thu",
    5 => "Fri",
    6 => "Sat",
    7 => "Sun"
  }

  def short_day_name(day_of_week), do: Map.get(@short_day_names, day_of_week, "")

  @doc """
  Gets or creates a meal plan for a given week (identified by the Monday date).
  """
  def get_or_create_plan_for_week(user_id, week_start) do
    week_start = normalize_to_monday(week_start)

    case Repo.get_by(MealPlan, user_id: user_id, week_start: week_start) do
      nil ->
        %MealPlan{}
        |> MealPlan.changeset(%{user_id: user_id, week_start: week_start})
        |> Repo.insert()

      plan ->
        {:ok, plan}
    end
    |> case do
      {:ok, plan} ->
        {:ok, Repo.preload(plan, entries: [:recipe])}

      error ->
        error
    end
  end

  @doc """
  Lists all meal plans for a user, ordered by week.
  """
  def list_plans(user_id) do
    MealPlan
    |> where(user_id: ^user_id)
    |> order_by(desc: :week_start)
    |> Repo.all()
    |> Repo.preload(entries: [:recipe])
  end

  @doc """
  Adds a recipe to a meal plan slot.
  """
  def add_entry(meal_plan, attrs) do
    # Find the next position for this slot
    position =
      from(e in MealPlanEntry,
        where: e.meal_plan_id == ^meal_plan.id,
        where: e.day_of_week == ^attrs.day_of_week,
        where: e.meal_type == ^attrs.meal_type,
        select: max(e.position)
      )
      |> Repo.one()
      |> case do
        nil -> 0
        max_pos -> max_pos + 1
      end

    %MealPlanEntry{}
    |> MealPlanEntry.changeset(
      Map.merge(attrs, %{meal_plan_id: meal_plan.id, position: position})
    )
    |> Repo.insert()
  end

  @doc """
  Removes an entry from a meal plan.
  """
  def remove_entry(entry_id) do
    case Repo.get(MealPlanEntry, entry_id) do
      nil -> {:error, :not_found}
      entry -> Repo.delete(entry)
    end
  end

  @doc """
  Generates an aggregated shopping list from a meal plan's recipes.
  Groups ingredients by name and sums quantities where possible.
  """
  def generate_shopping_list(meal_plan_id) do
    entries =
      from(e in MealPlanEntry,
        where: e.meal_plan_id == ^meal_plan_id,
        preload: [recipe: :ingredients]
      )
      |> Repo.all()

    entries
    |> Enum.flat_map(fn entry -> entry.recipe.ingredients end)
    |> Enum.group_by(fn ing -> {String.downcase(ing.name), ing.unit || ""} end)
    |> Enum.map(fn {{name, unit}, ingredients} ->
      total_quantity = merge_quantities(ingredients)

      %{
        name: name,
        quantity: total_quantity,
        unit: unit,
        checked: false
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Returns the Monday of the week containing the given date.
  """
  def normalize_to_monday(date) do
    day_of_week = Date.day_of_week(date)
    Date.add(date, -(day_of_week - 1))
  end

  @doc """
  Returns the week start dates for navigation (prev, current, next).
  """
  def week_navigation(week_start) do
    %{
      prev: Date.add(week_start, -7),
      current: week_start,
      next: Date.add(week_start, 7)
    }
  end

  defp merge_quantities(ingredients) do
    quantities = Enum.map(ingredients, & &1.quantity)

    if Enum.all?(quantities, &numeric?/1) do
      quantities
      |> Enum.map(&parse_number/1)
      |> Enum.sum()
      |> format_number()
    else
      Enum.join(quantities, " + ")
    end
  end

  defp numeric?(nil), do: false
  defp numeric?(""), do: false

  defp numeric?(str) do
    str = String.trim(str)
    # Match: "2", "0.5", "1/3", "1 1/2"
    Regex.match?(~r/^\d+(\.\d+)?$/, str) ||
      Regex.match?(~r/^\d+\/\d+$/, str) ||
      Regex.match?(~r/^\d+\s+\d+\/\d+$/, str)
  end

  defp parse_number(nil), do: 0.0
  defp parse_number(""), do: 0.0

  defp parse_number(str) do
    str = String.trim(str)

    cond do
      # Mixed fraction: "1 1/2"
      Regex.match?(~r/^\d+\s+\d+\/\d+$/, str) ->
        [whole, frac] = String.split(str, ~r/\s+/, parts: 2)
        parse_float(whole) + parse_fraction(frac)

      # Simple fraction: "1/3"
      Regex.match?(~r/^\d+\/\d+$/, str) ->
        parse_fraction(str)

      # Regular number
      true ->
        parse_float(str)
    end
  end

  defp parse_fraction(str) do
    case String.split(str, "/") do
      [num, den] ->
        n = parse_float(num)
        d = parse_float(den)
        if d == 0.0, do: 0.0, else: n / d

      _ ->
        0.0
    end
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {n, _} -> n
      :error -> 0.0
    end
  end

  defp format_number(n) when n == trunc(n), do: to_string(trunc(n))
  defp format_number(n), do: :erlang.float_to_binary(n, decimals: 1)
end

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

  def navigation_summary(user_id) do
    plan = get_plan_for_week(user_id, Date.utc_today())

    tonight =
      Enum.find(
        plan.entries,
        &(&1.day_of_week == Date.day_of_week(Date.utc_today()) && &1.meal_type == :dinner)
      )

    %{
      tonight: tonight && tonight.recipe,
      shopping_count: Enum.count(shopping_items(plan), &(&1.id not in plan.shopping_checked))
    }
  end

  def shopping_items(%MealPlan{id: nil}), do: []

  def shopping_items(plan) do
    extras =
      Enum.map(plan.shopping_extras, fn name ->
        %{
          id: "extra-" <> Base.url_encode64(name, padding: false),
          name: name,
          quantity: "",
          unit: "",
          recipes: [],
          checked: false
        }
      end)

    generate_shopping_list(plan.user_id, plan.id) ++ extras
  end

  def update_shopping_state(user_id, plan_id, attrs) do
    with {:ok, id} <- Ecto.UUID.cast(plan_id),
         %MealPlan{} = plan <- Repo.get_by(MealPlan, id: id, user_id: user_id) do
      case plan
           |> Ecto.Changeset.cast(attrs, [:shopping_checked, :shopping_extras])
           |> Repo.update() do
        {:ok, updated} -> {:ok, preload_owned_entries(updated, user_id)}
        error -> error
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def week_from_param(value) do
    case Date.from_iso8601(value || "") do
      {:ok, date} -> normalize_to_monday(date)
      _ -> normalize_to_monday(Date.utc_today())
    end
  end

  def cook_together_tip(plan) do
    plan = Repo.preload(plan, entries: [recipe: :steps])

    Enum.find_value(1..7, fn day ->
      recipes =
        plan.entries
        |> Enum.filter(&(&1.day_of_week == day))
        |> Enum.map(& &1.recipe)
        |> Enum.uniq_by(& &1.id)

      Enum.find_value(recipes, fn recipe ->
        simmer =
          Enum.find(
            recipe.steps,
            &((&1.duration_minutes || 0) >= 20 && Regex.match?(~r/\bsimmer/i, &1.instruction))
          )

        other = Enum.find(recipes, &(&1.id != recipe.id))

        if simmer && other,
          do: %{
            day: day_name(day),
            recipe: recipe.title,
            other: other.title,
            minutes: simmer.duration_minutes
          }
      end)
    end)
  end

  @doc """
  Gets or creates a meal plan for a given week (identified by the Monday date).
  """
  def get_or_create_plan_for_week(user_id, week_start) do
    week_start = normalize_to_monday(week_start)

    case Repo.get_by(MealPlan, user_id: user_id, week_start: week_start) do
      nil ->
        %MealPlan{user_id: user_id}
        |> MealPlan.changeset(%{week_start: week_start})
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id, :week_start])
        |> case do
          {:ok, _} -> {:ok, Repo.get_by!(MealPlan, user_id: user_id, week_start: week_start)}
          error -> error
        end

      plan ->
        {:ok, plan}
    end
    |> case do
      {:ok, plan} ->
        {:ok, preload_owned_entries(plan, user_id)}

      error ->
        error
    end
  end

  def get_plan_for_week(user_id, date) do
    week = normalize_to_monday(date)

    case Repo.get_by(MealPlan, user_id: user_id, week_start: week) do
      nil -> %MealPlan{user_id: user_id, week_start: week, entries: []}
      plan -> preload_owned_entries(plan, user_id)
    end
  end

  def replace_slot(user_id, date, day, meal, recipe_ids) do
    Repo.transaction(fn ->
      recipes =
        Enum.map(recipe_ids, fn id ->
          case Cookbook.Recipes.get_recipe(user_id, id) do
            {:ok, recipe} -> recipe
            {:error, reason} -> Repo.rollback(reason)
          end
        end)

      {:ok, plan} = get_or_create_plan_for_week(user_id, date)
      _ = Repo.one!(from p in MealPlan, where: p.id == ^plan.id, lock: "FOR UPDATE")

      from(e in MealPlanEntry,
        where: e.meal_plan_id == ^plan.id and e.day_of_week == ^day and e.meal_type == ^meal
      )
      |> Repo.delete_all()

      Enum.with_index(recipes, fn recipe, position ->
        %MealPlanEntry{meal_plan_id: plan.id, recipe_id: recipe.id}
        |> MealPlanEntry.changeset(%{day_of_week: day, meal_type: meal, position: position})
        |> Repo.insert!()
      end)

      get_plan_for_week(user_id, date)
    end)
  end

  def add_entry(user_id, plan_id, attrs) do
    with {:ok, id} <- Ecto.UUID.cast(plan_id),
         %MealPlan{} = plan <- Repo.get_by(MealPlan, id: id, user_id: user_id),
         {:ok, _} <- Cookbook.Recipes.get_recipe(user_id, attrs.recipe_id) do
      Repo.transaction(fn ->
        _ = Repo.one!(from p in MealPlan, where: p.id == ^plan.id, lock: "FOR UPDATE")

        case add_entry(plan, attrs) do
          {:ok, entry} -> entry
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    else
      _ -> {:error, :not_found}
    end
  end

  def remove_entry(user_id, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %MealPlanEntry{} = entry <-
           Repo.one(
             from e in MealPlanEntry,
               join: p in assoc(e, :meal_plan),
               where: e.id == ^id and p.user_id == ^user_id,
               select: e
           ) do
      Repo.delete(entry)
    else
      _ -> {:error, :not_found}
    end
  end

  def shopping_list_for_week(user_id, date) do
    plan = get_plan_for_week(user_id, date)
    if plan.id, do: shopping_list_for_plan(user_id, plan.id), else: []
  end

  def generate_shopping_list(user_id, plan_id) do
    with {:ok, id} <- Ecto.UUID.cast(plan_id),
         %MealPlan{} <- Repo.get_by(MealPlan, id: id, user_id: user_id) do
      shopping_list_for_plan(user_id, id)
    else
      _ -> []
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
    |> Enum.map(&preload_owned_entries(&1, user_id))
  end

  # Caller holds the plan lock and has checked recipe ownership.
  defp add_entry(meal_plan, attrs) do
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

    %MealPlanEntry{meal_plan_id: meal_plan.id, recipe_id: attrs.recipe_id}
    |> MealPlanEntry.changeset(
      Map.merge(attrs, %{meal_plan_id: meal_plan.id, position: position})
    )
    |> Repo.insert()
  end

  # Aggregate only after resolving an owner-scoped plan.
  defp shopping_list_for_plan(user_id, meal_plan_id) do
    entries =
      from(e in MealPlanEntry,
        join: recipe in assoc(e, :recipe),
        where: e.meal_plan_id == ^meal_plan_id,
        where: recipe.user_id == ^user_id,
        preload: [recipe: :ingredients]
      )
      |> Repo.all()

    entries
    |> Enum.flat_map(fn entry ->
      Enum.map(entry.recipe.ingredients, &{&1, entry.recipe.title})
    end)
    |> Enum.group_by(fn {ing, _} -> {String.downcase(ing.name), ing.unit || ""} end)
    |> Enum.map(fn {{name, unit}, sources} ->
      ingredients = Enum.map(sources, &elem(&1, 0))
      total_quantity = merge_quantities(ingredients)

      %{
        id: Base.url_encode64(name <> "\0" <> unit, padding: false),
        name: name,
        quantity: total_quantity,
        unit: unit,
        checked: false,
        recipes: sources |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp preload_owned_entries(plan, user_id) do
    entries =
      from e in MealPlanEntry,
        join: recipe in assoc(e, :recipe),
        where: recipe.user_id == ^user_id,
        preload: [recipe: recipe]

    Repo.preload(plan, [entries: entries], force: true)
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

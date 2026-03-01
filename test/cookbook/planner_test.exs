defmodule Cookbook.PlannerTest do
  use Cookbook.DataCase, async: true

  alias Cookbook.Planner
  alias Cookbook.Recipes
  alias Cookbook.Accounts

  @allowed_email "test@example.com"

  setup do
    {:ok, user} = Accounts.get_or_create_user_by_email(@allowed_email)

    {:ok, recipe} =
      Recipes.create_recipe(%{
        "title" => "Test Recipe",
        "user_id" => user.id,
        "ingredients" => %{
          "0" => %{"name" => "Flour", "quantity" => "500", "unit" => "g", "position" => "0"},
          "1" => %{"name" => "Sugar", "quantity" => "200", "unit" => "g", "position" => "1"}
        },
        "steps" => %{
          "0" => %{"instruction" => "Mix ingredients", "position" => "0"}
        }
      })

    %{user: user, recipe: recipe}
  end

  describe "get_or_create_plan_for_week/2" do
    test "creates a new plan for a week", %{user: user} do
      week_start = ~D[2026-02-23]
      assert {:ok, plan} = Planner.get_or_create_plan_for_week(user.id, week_start)
      assert plan.week_start == ~D[2026-02-23]
      assert plan.user_id == user.id
    end

    test "returns existing plan for the same week", %{user: user} do
      week_start = ~D[2026-02-23]
      {:ok, plan1} = Planner.get_or_create_plan_for_week(user.id, week_start)
      {:ok, plan2} = Planner.get_or_create_plan_for_week(user.id, week_start)
      assert plan1.id == plan2.id
    end

    test "normalizes to Monday", %{user: user} do
      # Feb 25 is a Wednesday
      {:ok, plan} = Planner.get_or_create_plan_for_week(user.id, ~D[2026-02-25])
      assert plan.week_start == ~D[2026-02-23]
    end
  end

  describe "add_entry/2 and remove_entry/1" do
    test "adds a recipe to a meal slot", %{user: user, recipe: recipe} do
      {:ok, plan} = Planner.get_or_create_plan_for_week(user.id, ~D[2026-02-23])

      {:ok, entry} =
        Planner.add_entry(plan, %{
          day_of_week: 1,
          meal_type: :lunch,
          recipe_id: recipe.id
        })

      assert entry.day_of_week == 1
      assert entry.meal_type == :lunch
      assert entry.recipe_id == recipe.id
    end

    test "removes an entry", %{user: user, recipe: recipe} do
      {:ok, plan} = Planner.get_or_create_plan_for_week(user.id, ~D[2026-02-23])

      {:ok, entry} =
        Planner.add_entry(plan, %{
          day_of_week: 1,
          meal_type: :lunch,
          recipe_id: recipe.id
        })

      {:ok, _} = Planner.remove_entry(entry.id)

      {:ok, updated_plan} = Planner.get_or_create_plan_for_week(user.id, ~D[2026-02-23])
      assert updated_plan.entries == []
    end
  end

  describe "generate_shopping_list/1" do
    test "aggregates ingredients from plan entries", %{user: user, recipe: recipe} do
      {:ok, plan} = Planner.get_or_create_plan_for_week(user.id, ~D[2026-02-23])

      # Add the same recipe to two slots
      Planner.add_entry(plan, %{day_of_week: 1, meal_type: :lunch, recipe_id: recipe.id})
      Planner.add_entry(plan, %{day_of_week: 2, meal_type: :dinner, recipe_id: recipe.id})

      list = Planner.generate_shopping_list(plan.id)

      flour = Enum.find(list, &(&1.name == "flour"))
      assert flour.quantity == "1000"
      assert flour.unit == "g"

      sugar = Enum.find(list, &(&1.name == "sugar"))
      assert sugar.quantity == "400"
    end

    test "sums fractional quantities", %{user: user} do
      {:ok, recipe} =
        Recipes.create_recipe(%{
          "title" => "Fraction Recipe",
          "user_id" => user.id,
          "ingredients" => %{
            "0" => %{"name" => "Pesto", "quantity" => "1/3", "unit" => "cup", "position" => "0"},
            "1" => %{"name" => "Pepper", "quantity" => "1/2", "unit" => "tsp", "position" => "1"}
          },
          "steps" => %{
            "0" => %{"instruction" => "Mix", "position" => "0"}
          }
        })

      {:ok, plan} = Planner.get_or_create_plan_for_week(user.id, ~D[2026-03-02])

      Planner.add_entry(plan, %{day_of_week: 1, meal_type: :lunch, recipe_id: recipe.id})
      Planner.add_entry(plan, %{day_of_week: 2, meal_type: :dinner, recipe_id: recipe.id})
      Planner.add_entry(plan, %{day_of_week: 3, meal_type: :lunch, recipe_id: recipe.id})

      list = Planner.generate_shopping_list(plan.id)

      pesto = Enum.find(list, &(&1.name == "pesto"))
      assert pesto.quantity == "1"

      pepper = Enum.find(list, &(&1.name == "pepper"))
      assert pepper.quantity == "1.5"
    end
  end

  describe "normalize_to_monday/1" do
    test "returns Monday for a Monday" do
      assert Planner.normalize_to_monday(~D[2026-02-23]) == ~D[2026-02-23]
    end

    test "returns Monday for a Wednesday" do
      assert Planner.normalize_to_monday(~D[2026-02-25]) == ~D[2026-02-23]
    end

    test "returns Monday for a Sunday" do
      assert Planner.normalize_to_monday(~D[2026-03-01]) == ~D[2026-02-23]
    end
  end
end

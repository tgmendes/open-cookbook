defmodule Cookbook.RecipesTest do
  use Cookbook.DataCase, async: true

  alias Cookbook.Recipes
  alias Cookbook.Accounts

  @allowed_email "test@example.com"

  setup do
    {:ok, user} = Accounts.get_or_create_user_by_email(@allowed_email)
    %{user: user}
  end

  defp recipe_attrs(user, overrides \\ %{}) do
    Map.merge(
      %{
        "title" => "Spaghetti Carbonara",
        "description" => "Classic Italian pasta",
        "servings" => 4,
        "prep_time_minutes" => 10,
        "cook_time_minutes" => 20,
        "source_type" => "manual",
        "tags" => ["italian", "pasta"],
        "user_id" => user.id,
        "ingredients" => %{
          "0" => %{"name" => "Spaghetti", "quantity" => "400", "unit" => "g", "position" => "0"},
          "1" => %{"name" => "Guanciale", "quantity" => "200", "unit" => "g", "position" => "1"},
          "2" => %{"name" => "Eggs", "quantity" => "4", "unit" => "", "position" => "2"}
        },
        "steps" => %{
          "0" => %{"instruction" => "Cook the pasta", "position" => "0", "duration_minutes" => "10"},
          "1" => %{"instruction" => "Fry the guanciale", "position" => "1", "duration_minutes" => "5"},
          "2" => %{"instruction" => "Mix everything together", "position" => "2"}
        }
      },
      overrides
    )
  end

  describe "create_recipe/1" do
    test "creates a recipe with ingredients and steps", %{user: user} do
      assert {:ok, recipe} = Recipes.create_recipe(recipe_attrs(user))
      assert recipe.title == "Spaghetti Carbonara"
      assert recipe.total_time_minutes == 30

      recipe = Recipes.get_recipe!(recipe.id)
      assert length(recipe.ingredients) == 3
      assert length(recipe.steps) == 3

      first_ingredient = Enum.find(recipe.ingredients, &(&1.position == 0))
      assert first_ingredient.name == "Spaghetti"
    end

    test "requires a title", %{user: user} do
      attrs = recipe_attrs(user, %{"title" => ""})
      assert {:error, changeset} = Recipes.create_recipe(attrs)
      assert errors_on(changeset).title
    end
  end

  describe "update_recipe/2" do
    test "updates the recipe title", %{user: user} do
      {:ok, recipe} = Recipes.create_recipe(recipe_attrs(user))
      {:ok, updated} = Recipes.update_recipe(recipe, %{"title" => "Updated Title"})
      assert updated.title == "Updated Title"
    end
  end

  describe "delete_recipe/1" do
    test "deletes the recipe", %{user: user} do
      {:ok, recipe} = Recipes.create_recipe(recipe_attrs(user))
      {:ok, _} = Recipes.delete_recipe(recipe)
      assert_raise Ecto.NoResultsError, fn -> Recipes.get_recipe!(recipe.id) end
    end
  end

  describe "list_recipes/2" do
    test "lists all recipes for a user", %{user: user} do
      {:ok, _} = Recipes.create_recipe(recipe_attrs(user))
      {:ok, _} = Recipes.create_recipe(recipe_attrs(user, %{"title" => "Another Recipe"}))
      assert length(Recipes.list_recipes(user.id)) == 2
    end

    test "searches by title", %{user: user} do
      {:ok, _} = Recipes.create_recipe(recipe_attrs(user))
      {:ok, _} = Recipes.create_recipe(recipe_attrs(user, %{"title" => "Chicken Curry"}))

      results = Recipes.list_recipes(user.id, search: "chicken")
      assert length(results) == 1
      assert hd(results).title == "Chicken Curry"
    end

    test "filters by tag", %{user: user} do
      {:ok, _} = Recipes.create_recipe(recipe_attrs(user))
      {:ok, _} = Recipes.create_recipe(recipe_attrs(user, %{"title" => "Sushi", "tags" => ["japanese"]}))

      results = Recipes.list_recipes(user.id, tag: "japanese")
      assert length(results) == 1
      assert hd(results).title == "Sushi"
    end
  end

  describe "list_tags/1" do
    test "returns unique tags for a user", %{user: user} do
      {:ok, _} = Recipes.create_recipe(recipe_attrs(user))
      {:ok, _} = Recipes.create_recipe(recipe_attrs(user, %{"title" => "Sushi", "tags" => ["japanese", "quick"]}))

      tags = Recipes.list_tags(user.id)
      assert "italian" in tags
      assert "pasta" in tags
      assert "japanese" in tags
      assert "quick" in tags
    end
  end
end

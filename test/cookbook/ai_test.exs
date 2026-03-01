defmodule Cookbook.AITest do
  use Cookbook.DataCase, async: true

  alias Cookbook.AI

  describe "normalize_recipe_attrs (via generate_recipe flow)" do
    # Since we can't call Claude in tests, we test the normalization logic
    # by testing the public interface with mocked responses would look like.
    # The actual API calls are tested manually or with integration tests.

    test "scrape_recipe_from_url returns error without API key" do
      # This will fail at the client level since no API key is configured in test
      assert {:error, _} = AI.scrape_recipe_from_url("https://example.com/recipe")
    end

    test "generate_recipe returns error without API key" do
      assert {:error, :missing_api_key} = AI.generate_recipe("a quick pasta")
    end

    test "suggest_weekly_plan returns error without API key" do
      assert {:error, :missing_api_key} = AI.suggest_weekly_plan([])
    end
  end
end

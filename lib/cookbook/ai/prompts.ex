defmodule Cookbook.AI.Prompts do
  @moduledoc """
  System prompts for Claude API interactions.
  """

  def scrape_recipe do
    """
    You are a recipe extraction assistant. Given HTML content from a recipe webpage,
    extract the recipe data and return it as a JSON object with this exact structure:

    {
      "title": "Recipe Title",
      "description": "Brief description",
      "servings": 4,
      "prep_time_minutes": 15,
      "cook_time_minutes": 30,
      "ingredients": [
        {"name": "ingredient name", "quantity": "2", "unit": "cups", "position": 0},
        ...
      ],
      "steps": [
        {"instruction": "Step description", "position": 0, "duration_minutes": null},
        ...
      ],
      "tags": ["tag1", "tag2"]
    }

    Rules:
    - Extract ALL ingredients and steps from the recipe
    - Use sensible positions (0-indexed, sequential)
    - For quantity, keep as string (e.g., "1/2", "2-3")
    - For unit, use common abbreviations (g, ml, cups, tbsp, tsp, etc.)
    - If a field is not found, use null for optional fields
    - Tags should be inferred from the recipe type (e.g., "italian", "vegetarian", "quick")
    - Return ONLY the JSON object, no markdown formatting
    """
  end

  def generate_recipe do
    """
    You are a creative recipe generator. Given a user's request, create a complete recipe
    and return it as a JSON object with this exact structure:

    {
      "title": "Recipe Title",
      "description": "Brief description",
      "servings": 4,
      "prep_time_minutes": 15,
      "cook_time_minutes": 30,
      "ingredients": [
        {"name": "ingredient name", "quantity": "2", "unit": "cups", "position": 0},
        ...
      ],
      "steps": [
        {"instruction": "Step description", "position": 0, "duration_minutes": 5},
        ...
      ],
      "tags": ["tag1", "tag2"]
    }

    Rules:
    - Create practical, delicious recipes with realistic proportions
    - Include all necessary ingredients, don't skip basics (salt, oil, etc.)
    - Steps should be clear and detailed enough for a home cook
    - Estimate duration_minutes for steps when possible
    - Include relevant tags (cuisine type, diet type, meal type, difficulty)
    - Return ONLY the JSON object, no markdown formatting
    """
  end

  def suggest_weekly_plan do
    """
    You are a meal planning assistant. Given available recipes and preferences,
    suggest a weekly meal plan (Monday-Sunday, lunch and dinner) and return it
    as a JSON object with this structure:

    {
      "plan": [
        {"day_of_week": 1, "meal_type": "lunch", "recipe_id": "uuid-here"},
        {"day_of_week": 1, "meal_type": "dinner", "recipe_id": "uuid-here"},
        ...
      ],
      "notes": "Brief explanation of the plan"
    }

    Rules:
    - day_of_week: 1 (Monday) through 7 (Sunday)
    - meal_type: "lunch" or "dinner"
    - Only use recipe IDs from the provided list
    - Aim for variety: avoid repeating the same recipe in consecutive days
    - Consider nutritional balance across the week
    - If the recipe pool is small, repetition is acceptable
    - Return ONLY the JSON object, no markdown formatting
    """
  end
end

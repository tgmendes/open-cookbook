defmodule Cookbook.AI do
  @moduledoc """
  The AI context. Handles recipe scraping, generation, and meal plan suggestions
  using the OpenRouter API.
  """

  alias Cookbook.AI.{Client, Prompts}

  @doc """
  Scrapes a recipe from a URL by fetching its HTML and sending to Claude for extraction.
  Returns `{:ok, recipe_attrs}` or `{:error, reason}`.
  """
  def scrape_recipe_from_url(url) do
    with {:ok, html} <- fetch_url(url),
         # Truncate to avoid exceeding token limits
         truncated = String.slice(html, 0, 100_000),
         {:ok, data} <- Client.chat_json(Prompts.scrape_recipe(), "Extract the recipe from this HTML:\n\n#{truncated}") do
      {:ok, normalize_recipe_attrs(data, %{"source_url" => url, "source_type" => "scraped"})}
    end
  end

  @doc """
  Generates a recipe from a free-text prompt using Claude.
  Returns `{:ok, recipe_attrs}` or `{:error, reason}`.
  """
  def generate_recipe(prompt) do
    case Client.chat_json(Prompts.generate_recipe(), prompt) do
      {:ok, data} ->
        {:ok, normalize_recipe_attrs(data, %{"source_type" => "generated"})}

      error ->
        error
    end
  end

  @doc """
  Suggests a weekly meal plan based on available recipes.
  Returns `{:ok, plan_data}` or `{:error, reason}`.
  """
  def suggest_weekly_plan(recipes, preferences \\ "") do
    recipes_summary =
      recipes
      |> Enum.map(fn r ->
        %{id: r.id, title: r.title, tags: r.tags || []}
      end)
      |> Jason.encode!()

    message = """
    Available recipes:
    #{recipes_summary}

    #{if preferences != "", do: "Preferences: #{preferences}", else: "No specific preferences."}

    Create a weekly meal plan using these recipes.
    """

    Client.chat_json(Prompts.suggest_weekly_plan(), message)
  end

  defp fetch_url(url) do
    case Req.get(url, receive_timeout: 15_000, redirect: true, max_redirects: 5) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, {:fetch_failed, reason}}
    end
  end

  defp normalize_recipe_attrs(data, extra) do
    ingredients =
      (data["ingredients"] || [])
      |> Enum.with_index()
      |> Enum.map(fn {ing, idx} ->
        %{
          "name" => ing["name"] || "",
          "quantity" => to_string(ing["quantity"] || ""),
          "unit" => ing["unit"] || "",
          "position" => to_string(ing["position"] || idx)
        }
      end)

    steps =
      (data["steps"] || [])
      |> Enum.with_index()
      |> Enum.map(fn {step, idx} ->
        %{
          "instruction" => step["instruction"] || "",
          "position" => to_string(step["position"] || idx),
          "duration_minutes" => to_string(step["duration_minutes"] || "")
        }
      end)

    Map.merge(
      %{
        "title" => data["title"] || "",
        "description" => data["description"] || "",
        "servings" => data["servings"],
        "prep_time_minutes" => data["prep_time_minutes"],
        "cook_time_minutes" => data["cook_time_minutes"],
        "tags" => data["tags"] || [],
        "ingredients" => ingredients |> Enum.with_index() |> Enum.map(fn {v, i} -> {to_string(i), v} end) |> Map.new(),
        "steps" => steps |> Enum.with_index() |> Enum.map(fn {v, i} -> {to_string(i), v} end) |> Map.new()
      },
      extra
    )
  end
end

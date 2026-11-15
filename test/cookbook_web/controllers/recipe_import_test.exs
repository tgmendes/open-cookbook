defmodule CookbookWeb.RecipeImportTest do
  use CookbookWeb.ConnCase, async: true
  alias Cookbook.{Accounts, Recipes, Planner}

  setup %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")
    {:ok, _, token} = Accounts.create_api_token(user, "Import")
    %{conn: put_req_header(conn, "authorization", "Bearer #{token}"), user: user}
  end

  defp recipe do
    %{
      "title" => "Roast broccoli",
      "servings" => 2,
      "prep_ahead" => "Chop the day before",
      "troubleshooting" => "Uncover if watery",
      "variations" => "Swap cauliflower",
      "freezer_friendly" => true,
      "freezer_notes" => "Freeze for a month; reheat until piping hot",
      "source_conversation_url" => "https://claude.ai/chat/example",
      "image_credit" => "A Photographer",
      "image_source_url" => "https://pexels.com/photo/example",
      "image_license" => "Pexels License",
      "image_match" => "approximate",
      "ingredients" => [
        %{"ref" => "broccoli", "name" => "Broccoli", "quantity_value" => 250, "unit" => "g"},
        %{
          "ref" => "oil",
          "name" => "Oil",
          "quantity_value" => 0.5,
          "quantity_text" => "1/2",
          "unit" => "tbsp"
        },
        %{"ref" => "salt", "name" => "Salt", "quantity_text" => "to taste"}
      ],
      "steps" => [
        %{
          "short_title" => "Roast the veg",
          "instruction" => "Roast {{broccoli}} with {{oil}}.",
          "ingredient_refs" => ["broccoli", "oil"]
        },
        %{"instruction" => "Season.", "ingredient_refs" => ["salt"]}
      ]
    }
  end

  defp create(conn, body) do
    conn
    |> put_req_header("idempotency-key", Ecto.UUID.generate())
    |> post("/api/v1/recipes", body)
  end

  test "complete import round-trips structured fields and array order", %{conn: conn} do
    data = create(conn, recipe()) |> json_response(201) |> Map.fetch!("data")
    assert data["prep_ahead"] == "Chop the day before"
    assert data["troubleshooting"] == "Uncover if watery"
    assert data["variations"] == "Swap cauliflower"
    assert data["freezer_friendly"] == true
    assert data["freezer_notes"] == recipe()["freezer_notes"]
    assert data["source_conversation_url"] == "https://claude.ai/chat/example"
    assert data["image_credit"] == "A Photographer"
    assert data["image_license"] == "Pexels License"
    assert data["image_match"] == "approximate"
    assert Enum.map(data["ingredients"], & &1["position"]) == [0, 1, 2]
    assert Enum.map(data["steps"], & &1["position"]) == [0, 1]
    assert hd(data["ingredients"])["quantity_value"] == 250
    assert hd(data["steps"])["ingredient_refs"] == ["broccoli", "oil"]
    fetched = conn |> get("/api/v1/recipes/#{data["id"]}") |> json_response(200)
    assert fetched["data"] == data
  end

  test "rejects dangling or duplicate ingredient references and negative quantities", %{
    conn: conn
  } do
    for body <- [
          put_in(recipe(), ["steps", Access.at(0), "ingredient_refs"], ["missing"]),
          put_in(recipe(), ["steps", Access.at(0), "instruction"], "Add {{missing}}"),
          put_in(recipe(), ["ingredients", Access.at(1), "ref"], "broccoli"),
          put_in(recipe(), ["ingredients", Access.at(0), "quantity_value"], -1),
          Map.put(recipe(), "source_conversation_url", "javascript:alert(1)")
        ] do
      assert create(conn, body) |> json_response(422)
    end
  end

  test "partial updates retain links and reject removal of referenced ingredients", %{conn: conn} do
    %{"data" => %{"id" => id}} = create(conn, recipe()) |> json_response(201)
    data = conn |> patch("/api/v1/recipes/#{id}", %{"title" => "Updated"}) |> json_response(200)
    assert hd(data["data"]["steps"])["ingredient_refs"] == ["broccoli", "oil"]

    assert conn
           |> recycle()
           |> patch("/api/v1/recipes/#{id}", %{"ingredients" => []})
           |> json_response(422)

    assert conn
           |> recycle()
           |> patch("/api/v1/recipes/#{id}", %{"ingredients" => [], "steps" => []})
           |> json_response(200)
  end

  test "freezer filter is owner-scoped", %{conn: conn, user: user} do
    %{"data" => %{"id" => id}} = create(conn, recipe()) |> json_response(201)
    {:ok, _} = Recipes.create_recipe(user.id, %{title: "Fresh only"})
    result = conn |> get("/api/v1/recipes?freezer_friendly=true") |> json_response(200)
    assert Enum.map(result["data"], & &1["id"]) == [id]

    assert conn
           |> recycle()
           |> get("/api/v1/recipes?freezer_friendly=maybe")
           |> json_response(422)
  end

  test "structured quantities scale and aggregate without text parsing", %{conn: conn, user: user} do
    %{"data" => %{"id" => id}} = create(conn, recipe()) |> json_response(201)
    stored = Recipes.get_recipe!(user.id, id)
    {:ok, scaled} = Cookbook.Recipes.Scaling.scale(stored, 4)
    assert hd(scaled.ingredients).quantity == "500"
    assert Decimal.equal?(hd(scaled.ingredients).quantity_value, Decimal.new(500))
    assert Enum.at(scaled.ingredients, 1).quantity == "1"
    assert Enum.at(scaled.ingredients, 2).quantity == "to taste"
    {:ok, _} = Planner.replace_slot(user.id, ~D[2026-11-16], 1, :dinner, [id])
    {:ok, _} = Planner.replace_slot(user.id, ~D[2026-11-16], 2, :dinner, [id])
    items = Planner.shopping_list_for_week(user.id, ~D[2026-11-16])
    assert Enum.find(items, &(&1.name == "broccoli")).quantity == "500"
    assert Enum.find(items, &(&1.name == "oil")).quantity == "1"
  end

  test "direct context writes also derive order from arrays", %{user: user} do
    {:ok, stored} =
      Recipes.create_recipe(user.id, %{
        title: "Ordered",
        ingredients: [%{name: "First", position: 99}, %{name: "Second", position: 0}],
        steps: [%{instruction: "First", position: 99}, %{instruction: "Second", position: 0}]
      })

    stored = Recipes.get_recipe!(user.id, stored.id)
    assert Enum.map(stored.ingredients, & &1.name) == ["First", "Second"]
    assert Enum.map(stored.steps, & &1.position) == [0, 1]
  end

  test "replacing nested arrays preserves supplied refs and derives the new order", %{conn: conn} do
    %{"data" => %{"id" => id}} = create(conn, recipe()) |> json_response(201)

    replacement =
      recipe()
      |> Map.take(["ingredients", "steps"])
      |> Map.update!("ingredients", &Enum.reverse/1)

    data =
      conn
      |> patch("/api/v1/recipes/#{id}", replacement)
      |> json_response(200)
      |> Map.fetch!("data")

    assert Enum.map(data["ingredients"], & &1["ref"]) == ["salt", "oil", "broccoli"]
    assert Enum.map(data["ingredients"], & &1["position"]) == [0, 1, 2]
    assert hd(data["steps"])["ingredient_refs"] == ["broccoli", "oil"]
  end

  test "legacy quantity inputs cannot bypass numeric limits", %{conn: conn} do
    body = %{
      "title" => "Invalid quantity",
      "ingredients" => [%{"name" => "Sugar", "quantity" => String.duplicate("9", 400)}]
    }

    assert create(conn, body) |> json_response(422)
  end
end

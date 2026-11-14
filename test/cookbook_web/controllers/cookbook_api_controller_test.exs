defmodule CookbookWeb.CookbookApiControllerTest do
  use CookbookWeb.ConnCase, async: true
  import Ecto.Query
  alias Cookbook.{Accounts, Recipes, Planner, Repo}

  setup %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")
    {:ok, token, raw} = Accounts.create_api_token(user, "API test")

    other =
      %Accounts.User{} |> Accounts.User.changeset(%{email: "other@example.com"}) |> Repo.insert!()

    %{
      conn: put_req_header(conn, "authorization", "Bearer #{raw}"),
      user: user,
      token: token,
      other: other
    }
  end

  defp attrs do
    %{
      "title" => "Lemon pasta",
      "servings" => 2,
      "prep_time_minutes" => 5,
      "cook_time_minutes" => 10,
      "source_type" => "generated",
      "tags" => ["quick"],
      "ingredients" => [%{"name" => "Pasta", "quantity" => "200", "unit" => "g"}],
      "steps" => [%{"instruction" => "Boil the pasta", "duration_minutes" => 10}]
    }
  end

  defp create(conn, body \\ attrs(), key \\ "recipe-request-1") do
    conn |> put_req_header("idempotency-key", key) |> post("/api/v1/recipes", body)
  end

  test "all API operations require a token, not a browser cookie", %{user: user} do
    conn =
      build_conn()
      |> init_test_session(%{user_id: user.id, authenticated_at: System.system_time(:second)})

    for {method, path} <- [
          {:get, "/api/v1/profile"},
          {:get, "/api/v1/recipes"},
          {:post, "/api/v1/recipes"},
          {:get, "/api/v1/recipes/#{Ecto.UUID.generate()}"},
          {:patch, "/api/v1/recipes/#{Ecto.UUID.generate()}"},
          {:delete, "/api/v1/recipes/#{Ecto.UUID.generate()}"},
          {:get, "/api/v1/meal-plans/2026-11-13"},
          {:put, "/api/v1/meal-plans/2026-11-13/slots/1/dinner"},
          {:get, "/api/v1/shopping-lists/2026-11-13"}
        ] do
      response = dispatch(recycle(conn), @endpoint, method, path, %{})
      assert %{"error" => %{"code" => "unauthorized"}} = json_response(response, 401)
    end
  end

  test "revoked and malformed bearer credentials are rejected", %{
    conn: conn,
    token: token,
    user: user
  } do
    :ok = Accounts.revoke_api_token(user, token.id)
    assert conn |> get("/api/v1/profile") |> json_response(401)

    assert build_conn()
           |> put_req_header("authorization", "Bearer bogus")
           |> get("/api/v1/profile")
           |> json_response(401)
  end

  test "profile contains unit preferences, not identity or secrets", %{conn: conn} do
    assert %{"data" => %{"unit_system" => "metric", "ingredient_units" => units} = profile} =
             conn |> get("/api/v1/profile") |> json_response(200)

    assert "g" in units
    refute Map.has_key?(profile, "email")
    refute Map.has_key?(profile, "token")
  end

  test "creates a recipe with ordered nested content and replays without duplication", %{
    conn: conn,
    user: user
  } do
    first = create(conn)

    assert %{
             "data" =>
               %{
                 "id" => id,
                 "total_time_minutes" => 15,
                 "ingredients" => [%{"position" => 0}],
                 "steps" => [%{"instruction" => "Boil the pasta"}]
               } = data
           } = json_response(first, 201)

    refute Map.has_key?(data, "user_id")
    assert json_response(create(recycle(conn)), 201) == json_response(first, 201)
    assert length(Recipes.list_recipes(user.id)) == 1

    assert %{"data" => %{"id" => ^id}} =
             conn |> recycle() |> get("/api/v1/recipes/#{id}") |> json_response(200)

    assert %{"error" => %{"code" => "conflict"}} =
             conn
             |> recycle()
             |> create(Map.put(attrs(), "title", "Different"))
             |> json_response(409)
  end

  test "concurrent matching creates store exactly one recipe", %{conn: conn, user: user} do
    supervisor = start_supervised!(Task.Supervisor)

    responses =
      1..2
      |> Enum.map(fn _ ->
        Task.Supervisor.async_nolink(supervisor, fn ->
          create(recycle(conn)) |> json_response(201)
        end)
      end)
      |> Enum.map(&Task.await/1)

    assert Enum.at(responses, 0) == Enum.at(responses, 1)
    assert length(Recipes.list_recipes(user.id)) == 1
  end

  test "creation requires a bounded idempotency key", %{conn: conn} do
    assert conn |> post("/api/v1/recipes", attrs()) |> json_response(422)
    assert create(recycle(conn), attrs(), String.duplicate("x", 129)) |> json_response(422)
  end

  test "expired creation receipts allow a fresh request", %{conn: conn, user: user} do
    assert create(conn) |> json_response(201)

    from(r in Cookbook.ApiRequest, where: r.user_id == ^user.id)
    |> Repo.update_all(set: [expires_at: ~U[2020-01-01 00:00:00Z]])

    assert create(recycle(conn), Map.put(attrs(), "title", "New recipe")) |> json_response(201)
    assert length(Recipes.list_recipes(user.id)) == 2
  end

  test "invalid input never writes partial recipes", %{conn: conn, user: user} do
    for invalid <- [
          %{"title" => ""},
          Map.put(attrs(), "servings", -1),
          Map.put(attrs(), "prep_time_minutes", -2),
          Map.put(attrs(), "ingredients", "bad"),
          Map.put(attrs(), "steps", [nil]),
          Map.put(attrs(), "ingredients", [%{"name" => "Pasta", "user_id" => user.id}]),
          Map.put(attrs(), "user_id", user.id),
          Map.put(attrs(), "unknown", true),
          Map.put(attrs(), "tags", nil),
          Map.put(attrs(), "source_type", nil),
          Map.put(attrs(), "source_url", "javascript:alert(1)"),
          Map.put(attrs(), "image_url", "data:text/html,test")
        ] do
      assert create(recycle(conn), invalid, Ecto.UUID.generate()) |> json_response(422)
    end

    assert [] == Recipes.list_recipes(user.id)
  end

  test "recipe collection filters and bounds pagination", %{conn: conn} do
    create(conn)
    create(recycle(conn), Map.put(attrs(), "title", "Bean soup"), "second")

    assert %{"data" => [%{"title" => "Lemon pasta"}]} =
             conn
             |> recycle()
             |> get("/api/v1/recipes?search=Lemon&tag=quick")
             |> json_response(200)

    assert %{"data" => [_], "meta" => %{"has_more" => true}} =
             conn |> recycle() |> get("/api/v1/recipes?limit=1") |> json_response(200)

    for query <- ["limit=101", "limit=-1", "offset=bad", "search[x]=bad"] do
      assert conn |> recycle() |> get("/api/v1/recipes?#{query}") |> json_response(422)
    end
  end

  test "foreign and malformed recipe IDs cannot be read, edited, or deleted", %{
    conn: conn,
    other: other
  } do
    {:ok, foreign} = Recipes.create_recipe(other.id, attrs())

    for id <- [foreign.id, "bad-id", Ecto.UUID.generate()], method <- [:get, :patch, :delete] do
      assert dispatch(recycle(conn), @endpoint, method, "/api/v1/recipes/#{id}", %{
               "title" => "hijack"
             })
             |> json_response(404)
    end

    assert {:ok, %{title: "Lemon pasta"}} = Recipes.get_recipe(other.id, foreign.id)
  end

  test "PATCH preserves omitted collections and replaces explicitly supplied arrays", %{
    conn: conn
  } do
    %{"data" => %{"id" => id}} = create(conn) |> json_response(201)

    assert %{"data" => %{"title" => "Updated", "ingredients" => [_], "steps" => [_]}} =
             conn
             |> recycle()
             |> patch("/api/v1/recipes/#{id}", %{"title" => "Updated"})
             |> json_response(200)

    assert %{"data" => %{"ingredients" => [], "steps" => [_]}} =
             conn
             |> recycle()
             |> patch("/api/v1/recipes/#{id}", %{"ingredients" => []})
             |> json_response(200)
  end

  test "empty plan and shopping reads normalize dates without creating records", %{conn: conn} do
    before = Repo.aggregate(Planner.MealPlan, :count)

    assert %{"data" => %{"week_start" => "2026-11-09", "entries" => []}} =
             conn |> get("/api/v1/meal-plans/2026-11-13") |> json_response(200)

    assert %{"data" => %{"week_start" => "2026-11-09", "items" => []}} =
             conn |> recycle() |> get("/api/v1/shopping-lists/2026-11-13") |> json_response(200)

    assert before == Repo.aggregate(Planner.MealPlan, :count)
  end

  test "legacy cross-owner meal references cannot expose foreign recipes", %{
    conn: conn,
    user: user,
    other: other
  } do
    {:ok, foreign} =
      Recipes.create_recipe(other.id, Map.put(attrs(), "title", "Secret foreign recipe"))

    {:ok, plan} = Planner.get_or_create_plan_for_week(user.id, ~D[2026-11-09])

    Repo.insert!(%Planner.MealPlanEntry{
      meal_plan_id: plan.id,
      recipe_id: foreign.id,
      day_of_week: 1,
      meal_type: :dinner,
      position: 0
    })

    assert %{"data" => %{"entries" => []}} =
             conn |> get("/api/v1/meal-plans/2026-11-09") |> json_response(200)

    assert %{"data" => %{"items" => []}} =
             conn |> recycle() |> get("/api/v1/shopping-lists/2026-11-09") |> json_response(200)
  end

  test "slot replacement is idempotent and shopping totals reflect repeated meals", %{conn: conn} do
    %{"data" => %{"id" => id}} = create(conn) |> json_response(201)
    path = "/api/v1/meal-plans/2026-11-13/slots/1/dinner"

    for _ <- 1..2 do
      assert conn |> recycle() |> put(path, %{"recipe_ids" => [id]}) |> json_response(200)
    end

    assert conn
           |> recycle()
           |> put("/api/v1/meal-plans/2026-11-09/slots/2/lunch", %{"recipe_ids" => [id]})
           |> json_response(200)

    assert %{"data" => %{"entries" => [_, _]}} =
             conn |> recycle() |> get("/api/v1/meal-plans/2026-11-09") |> json_response(200)

    assert %{"data" => %{"items" => [%{"name" => "pasta", "quantity" => "400", "unit" => "g"}]}} =
             conn |> recycle() |> get("/api/v1/shopping-lists/2026-11-09") |> json_response(200)

    assert conn |> recycle() |> put(path, %{"recipe_ids" => []}) |> json_response(200)

    assert %{"data" => %{"entries" => [_]}} =
             conn |> recycle() |> get("/api/v1/meal-plans/2026-11-09") |> json_response(200)
  end

  test "invalid or foreign recipes cannot replace a valid slot", %{conn: conn, other: other} do
    %{"data" => %{"id" => id}} = create(conn) |> json_response(201)
    {:ok, foreign} = Recipes.create_recipe(other.id, attrs())
    path = "/api/v1/meal-plans/2026-11-09/slots/1/dinner"
    assert conn |> recycle() |> put(path, %{"recipe_ids" => [id]}) |> json_response(200)

    for invalid <- [
          %{"recipe_ids" => [foreign.id]},
          %{"recipe_ids" => ["bad-id"]},
          %{"recipe_ids" => nil},
          %{"recipe_ids" => [id], "user_id" => other.id}
        ] do
      response = conn |> recycle() |> put(path, invalid)
      assert response.status in [404, 422]
    end

    assert %{"data" => %{"entries" => [%{"recipe_id" => ^id}]}} =
             conn |> recycle() |> get("/api/v1/meal-plans/2026-11-09") |> json_response(200)

    for path <- ["/api/v1/meal-plans/bad-date", "/api/v1/shopping-lists/bad-date"] do
      assert conn |> recycle() |> get(path) |> json_response(422)
    end
  end

  test "deleting a recipe removes its meal references", %{conn: conn} do
    %{"data" => %{"id" => id}} = create(conn) |> json_response(201)

    conn
    |> recycle()
    |> put("/api/v1/meal-plans/2026-11-09/slots/1/dinner", %{"recipe_ids" => [id]})

    assert conn |> recycle() |> delete("/api/v1/recipes/#{id}") |> response(204) == ""
    assert [] == Repo.all(from e in Planner.MealPlanEntry, select: e.id)
  end
end

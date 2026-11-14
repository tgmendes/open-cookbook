defmodule CookbookWeb.OpenAPIControllerTest do
  use CookbookWeb.ConnCase, async: true
  alias Cookbook.Accounts

  test "exports a credential-free OpenAPI contract for every cookbook API operation", %{
    conn: conn
  } do
    spec = conn |> get("/api/openapi.json") |> json_response(200)
    assert spec["openapi"] == "3.0.3"
    assert spec["security"] == [%{"cookbookToken" => []}]
    assert spec["components"]["securitySchemes"]["cookbookToken"]["scheme"] == "bearer"
    paths = spec["paths"]
    assert paths["/api/v1/recipes"]["post"]["operationId"] == "create_recipe"

    assert Enum.any?(
             paths["/api/v1/recipes"]["post"]["parameters"],
             &(&1["name"] == "Idempotency-Key" and &1["required"])
           )

    actual =
      Phoenix.Router.routes(CookbookWeb.Router)
      |> Enum.filter(&String.starts_with?(&1.path, "/api/v1/"))
      |> Enum.map(fn route ->
        {String.replace(route.path, ~r/:([a-z_]+)/, "{\\1}"),
         route.verb |> to_string() |> String.downcase()}
      end)
      |> MapSet.new()

    advertised =
      for {path, operations} <- paths,
          {method, _} <- operations,
          into: MapSet.new(),
          do: {path, method}

    assert actual == advertised
    operations = for {_path, verbs} <- paths, {_verb, operation} <- verbs, do: operation
    ids = Enum.map(operations, & &1["operationId"])
    assert length(ids) == length(Enum.uniq(ids))

    for operation <- operations do
      refute Map.has_key?(operation, "security")
      assert operation["responses"]["401"]
    end

    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")
    {:ok, _, token} = Accounts.create_api_token(user, "Contract test")

    recipe =
      conn
      |> recycle()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("idempotency-key", "contract")
      |> post("/api/v1/recipes", %{
        "title" => "Contract pasta",
        "ingredients" => [%{"name" => "Pasta", "quantity" => "1/2"}],
        "steps" => [%{"instruction" => "Boil"}]
      })
      |> json_response(201)

    schema = spec["components"]["schemas"]["Recipe"]
    assert Enum.all?(schema["required"], &Map.has_key?(recipe["data"], &1))
    assert recipe["data"]["ingredients"] |> hd() |> Map.fetch!("quantity") == "1/2"

    assert spec["components"]["schemas"]["IngredientInput"]["properties"]["quantity"]["type"] ==
             "string"

    refute Map.has_key?(schema["properties"], "user_id")
  end
end

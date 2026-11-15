defmodule CookbookWeb.RecipeImageTest do
  use CookbookWeb.ConnCase, async: false
  alias Cookbook.{Accounts, Recipes, Repo}

  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aL1sAAAAASUVORK5CYII="
       )

  setup %{conn: conn} do
    original = Application.get_env(:cookbook, :image_storage)

    Application.put_env(:cookbook, :image_storage,
      endpoint: "https://example.r2.cloudflarestorage.com",
      bucket: "photos",
      access_key_id: "test-key",
      secret_access_key: "test-secret",
      request_options: [plug: {Req.Test, __MODULE__}]
    )

    on_exit(fn ->
      if original,
        do: Application.put_env(:cookbook, :image_storage, original),
        else: Application.delete_env(:cookbook, :image_storage)
    end)

    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")
    {:ok, _, token} = Accounts.create_api_token(user, "Photos")
    {:ok, recipe} = Recipes.create_recipe(user.id, %{title: "Soup"})
    %{conn: put_req_header(conn, "authorization", "Bearer #{token}"), user: user, recipe: recipe}
  end

  defp params(path) do
    File.write!(path, @png)

    %{
      "file" => %Plug.Upload{path: path, filename: "../../unsafe.png", content_type: "image/png"},
      "image_credit" => "Photographer",
      "image_source_url" => "https://pexels.com/photo/example",
      "image_license" => "Pexels License",
      "image_match" => "approximate"
    }
  end

  @tag :tmp_dir
  test "uploads signed bytes to owned storage and saves attribution", %{
    conn: conn,
    recipe: recipe,
    user: user,
    tmp_dir: dir
  } do
    Req.Test.stub(__MODULE__, fn request ->
      assert request.method == "PUT"
      assert request.request_path =~ "/photos/recipes/#{user.id}/#{recipe.id}/"

      assert get_req_header(request, "authorization")
             |> hd()
             |> String.starts_with?("AWS4-HMAC-SHA256 ")

      assert get_req_header(request, "content-type") == ["image/png"]
      {:ok, bytes, request} = Plug.Conn.read_body(request)
      assert bytes == @png
      send_resp(request, 200, "")
    end)

    data =
      conn
      |> post("/api/v1/recipes/#{recipe.id}/image", params(Path.join(dir, "photo.png")))
      |> json_response(200)
      |> Map.fetch!("data")

    assert data["image_url"] =~ CookbookWeb.Endpoint.url() <> "/recipes/#{recipe.id}/image/"
    assert data["image_credit"] == "Photographer"
    assert data["image_license"] == "Pexels License"
    assert data["image_match"] == "approximate"
    assert Recipes.get_recipe!(user.id, recipe.id).image_url == data["image_url"]
  end

  @tag :tmp_dir
  test "owned photos require browser sign-in and recipe ownership", %{
    conn: conn,
    recipe: recipe,
    user: user,
    tmp_dir: dir
  } do
    Req.Test.stub(__MODULE__, fn request ->
      case request.method do
        "PUT" ->
          send_resp(request, 200, "")

        "GET" ->
          assert get_req_header(request, "authorization")
                 |> hd()
                 |> String.starts_with?("AWS4-HMAC-SHA256 ")

          request |> put_resp_content_type("image/png") |> send_resp(200, @png)
      end
    end)

    %{"data" => %{"image_url" => url}} =
      conn
      |> post("/api/v1/recipes/#{recipe.id}/image", params(Path.join(dir, "photo.png")))
      |> json_response(200)

    path = URI.parse(url).path

    response =
      build_conn() |> log_in_user(user) |> put_req_header("accept", "image/png") |> get(path)

    assert response(response, 200) == @png
    assert get_resp_header(response, "content-type") == ["image/png"]
    assert get_resp_header(response, "cache-control") |> hd() |> String.contains?("no-store")
    assert build_conn() |> get(path) |> redirected_to() == "/login"

    {:ok, _} =
      Recipes.update_recipe(user.id, recipe.id, %{image_url: "https://example.com/replaced.png"})

    assert build_conn() |> log_in_user(user) |> get(path) |> response(404)
  end

  @tag :tmp_dir
  test "rejects invalid images, oversize files, and missing attribution before upload", %{
    conn: conn,
    recipe: recipe,
    tmp_dir: dir
  } do
    path = Path.join(dir, "photo.png")
    original = params(path)

    assert conn
           |> post("/api/v1/recipes/#{recipe.id}/image", Map.delete(original, "image_license"))
           |> json_response(422)

    File.write!(path, "<svg onload='alert(1)'></svg>")

    assert conn
           |> recycle()
           |> post("/api/v1/recipes/#{recipe.id}/image", original)
           |> json_response(422)

    File.write!(path, :binary.copy("x", 5_000_001))

    assert conn
           |> recycle()
           |> post("/api/v1/recipes/#{recipe.id}/image", original)
           |> json_response(422)
  end

  @tag :tmp_dir
  test "storage failures do not change the recipe and unavailable storage is explicit", %{
    conn: conn,
    recipe: recipe,
    user: user,
    tmp_dir: dir
  } do
    Req.Test.stub(__MODULE__, fn request -> send_resp(request, 500, "Upstream failed") end)
    body = params(Path.join(dir, "photo.png"))

    assert conn |> post("/api/v1/recipes/#{recipe.id}/image", body) |> json_response(503) == %{
             "error" => %{"code" => "storage_unavailable"}
           }

    assert Recipes.get_recipe!(user.id, recipe.id).image_url == nil
    Application.delete_env(:cookbook, :image_storage)

    assert conn
           |> recycle()
           |> post("/api/v1/recipes/#{recipe.id}/image", body)
           |> json_response(503)
  end

  @tag :tmp_dir
  test "uploads require authentication and recipe ownership", %{conn: conn, tmp_dir: dir} do
    other =
      %Accounts.User{} |> Accounts.User.changeset(%{email: "other@example.com"}) |> Repo.insert!()

    {:ok, other_recipe} = Recipes.create_recipe(other.id, %{title: "Private"})
    body = params(Path.join(dir, "photo.png"))
    assert conn |> post("/api/v1/recipes/#{other_recipe.id}/image", body) |> json_response(404)

    assert build_conn()
           |> post("/api/v1/recipes/#{other_recipe.id}/image", body)
           |> json_response(401)
  end
end

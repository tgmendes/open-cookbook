defmodule Cookbook.RecipeImages do
  @moduledoc "Owner-scoped, size-limited recipe photo uploads to Cloudflare R2."
  alias Cookbook.Recipes.Recipe
  @max_bytes 5_000_000
  @metadata ~w(image_credit image_source_url image_license image_match)

  def upload(recipe, params) do
    with true <- Enum.all?(Map.keys(params), &(&1 in ["file" | @metadata])),
         %Plug.Upload{} = file <- params["file"],
         true <-
           Enum.all?(~w(image_credit image_source_url image_license), fn key ->
             is_binary(params[key]) and String.trim(params[key]) != "" and
               String.length(params[key]) <= 20_000
           end),
         changeset <- Recipe.changeset(recipe, Map.take(params, @metadata)),
         true <- changeset.valid?,
         {:ok, %{size: size}} when size > 0 and size <= @max_bytes <- File.stat(file.path),
         {:ok, bytes} <- File.read(file.path),
         {:ok, type, extension} <- image_type(bytes),
         {:ok, url} <- store(recipe, bytes, type, extension) do
      {:ok, Map.put(Map.take(params, @metadata), "image_url", url)}
    else
      {:error, :storage_unavailable} = error -> error
      _ -> {:error, :invalid_input}
    end
  end

  defp image_type(<<137, 80, 78, 71, 13, 10, 26, 10, _::binary>>), do: {:ok, "image/png", "png"}
  defp image_type(<<255, 216, 255, _::binary>>), do: {:ok, "image/jpeg", "jpg"}

  defp image_type(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>),
    do: {:ok, "image/webp", "webp"}

  defp image_type(_), do: {:error, :invalid_input}

  defp store(recipe, bytes, type, extension) do
    config = Application.get_env(:cookbook, :image_storage, [])

    if configured?(config) do
      digest = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
      key = "recipes/#{recipe.user_id}/#{recipe.id}/#{digest}.#{extension}"

      options =
        storage_options(config, key) ++
          [
            body: bytes,
            headers: [
              {"content-type", type}
            ]
          ]

      case Req.put(Keyword.merge(options, Keyword.get(config, :request_options, []))) do
        {:ok, %{status: status}} when status in 200..299 ->
          {:ok, image_url(recipe.id, "#{digest}.#{extension}")}

        _ ->
          {:error, :storage_unavailable}
      end
    else
      {:error, :storage_unavailable}
    end
  end

  def read(recipe, filename) do
    if Regex.match?(~r/^[a-f0-9]{64}\.(png|jpg|webp)$/, filename) and
         recipe.image_url == image_url(recipe.id, filename) do
      read_object("recipes/#{recipe.user_id}/#{recipe.id}/#{filename}", filename)
    else
      {:error, :not_found}
    end
  end

  defp image_url(recipe_id, filename),
    do: CookbookWeb.Endpoint.url() <> "/recipes/#{recipe_id}/image/#{filename}"

  defp read_object(key, filename) do
    config = Application.get_env(:cookbook, :image_storage, [])

    if configured?(config) do
      options = storage_options(config, key)

      case Req.get(Keyword.merge(options, Keyword.get(config, :request_options, []))) do
        {:ok, %{status: 200, body: bytes}}
        when is_binary(bytes) and byte_size(bytes) <= @max_bytes ->
          type =
            case Path.extname(filename) do
              ".png" -> "image/png"
              ".jpg" -> "image/jpeg"
              ".webp" -> "image/webp"
            end

          {:ok, bytes, type}

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        _ ->
          {:error, :storage_unavailable}
      end
    else
      {:error, :storage_unavailable}
    end
  end

  defp storage_options(config, key) do
    [
      url: String.trim_trailing(config[:endpoint], "/") <> "/#{config[:bucket]}/#{key}",
      aws_sigv4: [
        access_key_id: config[:access_key_id],
        secret_access_key: config[:secret_access_key],
        region: "auto",
        service: "s3"
      ],
      retry: false,
      redirect: false,
      decode_body: false,
      receive_timeout: 30_000
    ]
  end

  defp configured?(config) do
    Enum.all?(
      [:endpoint, :bucket, :access_key_id, :secret_access_key],
      &(is_binary(config[&1]) and config[&1] != "")
    ) and
      valid_endpoint?(config[:endpoint]) and
      Regex.match?(~r/^[a-z0-9][a-z0-9.-]*$/, config[:bucket])
  end

  defp valid_endpoint?(endpoint) do
    uri = URI.parse(endpoint)

    uri.scheme == "https" and is_binary(uri.host) and uri.host != "" and is_nil(uri.userinfo) and
      is_nil(uri.query) and is_nil(uri.fragment)
  end
end

defmodule CookbookWeb.ApiInput do
  @moduledoc false

  @strings ~w(title description source_url source_type image_url notes prep_ahead troubleshooting variations freezer_notes source_conversation_url image_credit image_source_url image_license image_match)
  @numbers ~w(servings prep_time_minutes cook_time_minutes)
  @fields @strings ++ @numbers ++ ~w(tags ingredients steps freezer_friendly)

  def recipe(attrs) when is_map(attrs) do
    with true <- Enum.all?(Map.keys(attrs), &(&1 in @fields)),
         true <- Enum.all?(@strings, &valid_string?(attrs[&1])),
         true <- Enum.all?(@numbers, &(is_nil(attrs[&1]) or is_integer(attrs[&1]))),
         true <-
           not Map.has_key?(attrs, "freezer_friendly") or is_boolean(attrs["freezer_friendly"]),
         true <-
           not Map.has_key?(attrs, "tags") or
             (is_list(attrs["tags"]) and length(attrs["tags"]) <= 100 and
                Enum.all?(attrs["tags"], &is_binary/1)),
         true <-
           not Map.has_key?(attrs, "source_type") or
             attrs["source_type"] in ["manual", "scraped", "generated"],
         {:ok, attrs} <-
           collection(
             attrs,
             "ingredients",
             ~w(name quantity quantity_value quantity_text ref unit group_name),
             ~w(name quantity quantity_text ref unit group_name)
           ),
         {:ok, attrs} <-
           collection(
             attrs,
             "steps",
             ~w(instruction short_title duration_minutes ingredient_refs),
             ~w(instruction short_title)
           ) do
      {:ok, attrs}
    else
      _ -> {:error, :invalid_input}
    end
  end

  def recipe(_), do: {:error, :invalid_input}

  defp valid_string?(value),
    do: is_nil(value) or (is_binary(value) and String.length(value) <= 20_000)

  defp collection(attrs, key, allowed, strings) do
    if Map.has_key?(attrs, key) do
      items = attrs[key]

      if is_list(items) and length(items) <= 200 and
           Enum.all?(items, fn item ->
             is_map(item) and Enum.all?(Map.keys(item), &(&1 in allowed)) and
               Enum.all?(strings, &valid_string?(item[&1])) and
               (key != "ingredients" or is_nil(item["quantity_value"]) or
                  is_number(item["quantity_value"])) and
               (key != "steps" or not Map.has_key?(item, "ingredient_refs") or
                  (is_list(item["ingredient_refs"]) and length(item["ingredient_refs"]) <= 200 and
                     Enum.all?(item["ingredient_refs"], &is_binary/1))) and
               (key != "steps" or is_nil(item["duration_minutes"]) or
                  is_integer(item["duration_minutes"]))
           end) do
        positioned =
          Enum.with_index(items, fn item, index -> Map.put(item, "position", index) end)

        {:ok, Map.put(attrs, key, positioned)}
      else
        {:error, :invalid_input}
      end
    else
      {:ok, attrs}
    end
  end

  def pagination(params) do
    with true <- Enum.all?(~w(search tag), &(is_nil(params[&1]) or is_binary(params[&1]))),
         {:ok, freezer} <- boolean(params["freezer_friendly"]),
         {:ok, limit} <- integer(Map.get(params, "limit", "50")),
         {:ok, offset} <- integer(Map.get(params, "offset", "0")),
         true <- limit in 1..100 and offset >= 0 do
      {:ok,
       [
         search: params["search"],
         tag: params["tag"],
         freezer_friendly: freezer,
         limit: limit,
         offset: offset
       ]}
    else
      _ -> {:error, :invalid_input}
    end
  end

  defp boolean(nil), do: {:ok, nil}
  defp boolean("true"), do: {:ok, true}
  defp boolean("false"), do: {:ok, false}
  defp boolean(_), do: {:error, :invalid_input}

  def integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> {:ok, number}
      _ -> {:error, :invalid_input}
    end
  end

  def integer(_), do: {:error, :invalid_input}

  def date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      _ -> {:error, :invalid_input}
    end
  end

  def date(_), do: {:error, :invalid_input}

  def slot(params, body) do
    with {:ok, day} <- integer(params["day"]),
         true <- day in 1..7,
         meal when meal in ["lunch", "dinner"] <- params["meal"],
         true <- is_map(body) and Map.keys(body) == ["recipe_ids"],
         ids when is_list(ids) and length(ids) <= 50 <- body["recipe_ids"],
         true <- Enum.all?(ids, &is_binary/1) do
      {:ok, day, if(meal == "lunch", do: :lunch, else: :dinner), ids}
    else
      _ -> {:error, :invalid_input}
    end
  end
end

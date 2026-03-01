defmodule Cookbook.AI.Client do
  @moduledoc """
  HTTP client wrapper for the OpenRouter API.
  """

  @api_url "https://openrouter.ai/api/v1/chat/completions"
  @model "anthropic/claude-sonnet-4"
  @max_tokens 4096

  require Logger

  def chat(system_prompt, user_message, opts \\ []) do
    api_key = api_key()

    if is_nil(api_key) || api_key == "" do
      Logger.warning("OpenRouter API key is missing")
      {:error, :missing_api_key}
    else
      model = Keyword.get(opts, :model, @model)
      max_tokens = Keyword.get(opts, :max_tokens, @max_tokens)

      body =
        Jason.encode!(%{
          model: model,
          max_tokens: max_tokens,
          messages: [
            %{role: "system", content: system_prompt},
            %{role: "user", content: user_message}
          ]
        })

      headers = [
        {"content-type", "application/json"},
        {"authorization", "Bearer #{api_key}"}
      ]

      Logger.debug("Calling OpenRouter API with model: #{model}")

      result = Req.post(@api_url, body: body, headers: headers, receive_timeout: 60_000)

      case result do
        {:ok, %{status: 200, body: response_body}} ->
          Logger.debug("OpenRouter API success")
          extract_text(response_body)

        {:ok, %{status: status, body: response_body}} ->
          Logger.error("OpenRouter API error: #{status} - #{inspect(response_body)}")
          {:error, {:api_error, status, response_body}}

        {:error, reason} ->
          Logger.error("OpenRouter API request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end
  end

  def chat_json(system_prompt, user_message, opts \\ []) do
    case chat(system_prompt, user_message, opts) do
      {:ok, text} -> parse_json_response(text)
      error -> error
    end
  end

  def chat_vision(system_prompt, text_message, image_base64, opts \\ []) do
    api_key = api_key()

    if is_nil(api_key) || api_key == "" do
      Logger.warning("OpenRouter API key is missing")
      {:error, :missing_api_key}
    else
      model = Keyword.get(opts, :model, @model)
      max_tokens = Keyword.get(opts, :max_tokens, @max_tokens)

      body =
        Jason.encode!(%{
          model: model,
          max_tokens: max_tokens,
          messages: [
            %{role: "system", content: system_prompt},
            %{
              role: "user",
              content: [
                %{type: "image_url", image_url: %{url: "data:image/jpeg;base64,#{image_base64}"}},
                %{type: "text", text: text_message}
              ]
            }
          ]
        })

      headers = [
        {"content-type", "application/json"},
        {"authorization", "Bearer #{api_key}"}
      ]

      Logger.debug("Calling OpenRouter API (vision) with model: #{model}")

      result = Req.post(@api_url, body: body, headers: headers, receive_timeout: 60_000)

      case result do
        {:ok, %{status: 200, body: response_body}} ->
          Logger.debug("OpenRouter API (vision) success")
          extract_text(response_body)

        {:ok, %{status: status, body: response_body}} ->
          Logger.error("OpenRouter API (vision) error: #{status} - #{inspect(response_body)}")
          {:error, {:api_error, status, response_body}}

        {:error, reason} ->
          Logger.error("OpenRouter API (vision) request failed: #{inspect(reason)}")
          {:error, {:request_failed, reason}}
      end
    end
  end

  def chat_vision_json(system_prompt, text_message, image_base64, opts \\ []) do
    case chat_vision(system_prompt, text_message, image_base64, opts) do
      {:ok, text} -> parse_json_response(text)
      error -> error
    end
  end

  defp extract_text(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    {:ok, content}
  end

  defp extract_text(other) do
    {:error, {:unexpected_response, other}}
  end

  defp parse_json_response(text) do
    # Try to extract JSON from the response, handling potential markdown code blocks
    json_text =
      case Regex.run(~r/```(?:json)?\s*\n?([\s\S]*?)\n?```/, text) do
        [_, json] -> json
        nil -> text
      end

    case Jason.decode(json_text) do
      {:ok, data} -> {:ok, data}
      {:error, _} -> {:error, {:json_parse_error, text}}
    end
  end

  defp api_key do
    Application.get_env(:cookbook, :openrouter_api_key)
  end
end

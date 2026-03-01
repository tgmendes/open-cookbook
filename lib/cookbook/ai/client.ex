defmodule Cookbook.AI.Client do
  @moduledoc """
  HTTP client wrapper for the Claude API.
  """

  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-sonnet-4-20250514"
  @max_tokens 4096

  def chat(system_prompt, user_message, opts \\ []) do
    api_key = api_key()

    if is_nil(api_key) || api_key == "" do
      {:error, :missing_api_key}
    else
      model = Keyword.get(opts, :model, @model)
      max_tokens = Keyword.get(opts, :max_tokens, @max_tokens)

      body =
        Jason.encode!(%{
          model: model,
          max_tokens: max_tokens,
          system: system_prompt,
          messages: [%{role: "user", content: user_message}]
        })

      headers = [
        {"content-type", "application/json"},
        {"x-api-key", api_key},
        {"anthropic-version", "2023-06-01"}
      ]

      case Req.post(@api_url, body: body, headers: headers, receive_timeout: 60_000) do
        {:ok, %{status: 200, body: response_body}} ->
          extract_text(response_body)

        {:ok, %{status: status, body: response_body}} ->
          {:error, {:api_error, status, response_body}}

        {:error, reason} ->
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

  defp extract_text(%{"content" => [%{"type" => "text", "text" => text} | _]}) do
    {:ok, text}
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
    Application.get_env(:cookbook, :anthropic_api_key)
  end
end

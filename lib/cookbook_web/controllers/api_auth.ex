defmodule CookbookWeb.ApiAuth do
  @moduledoc "Token-only API authentication. Browser cookies never authorize API requests."
  import Plug.Conn
  alias Cookbook.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = put_resp_header(conn, "cache-control", "no-store")

    with [header] <- get_req_header(conn, "authorization"),
         [scheme, token] <- String.split(header, " ", parts: 2),
         true <- String.downcase(scheme) == "bearer",
         {:ok, user} <- Accounts.authenticate_api_token(token) do
      conn |> assign(:current_user, user) |> assign(:current_scope, %{user: user})
    else
      _ ->
        conn
        |> put_resp_header("www-authenticate", "Bearer")
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: %{code: "unauthorized"}})
        |> halt()
    end
  end
end

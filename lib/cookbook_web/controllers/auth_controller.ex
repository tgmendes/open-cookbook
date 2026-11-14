defmodule CookbookWeb.AuthController do
  use CookbookWeb, :controller

  alias Cookbook.Accounts

  def callback(conn, %{"token" => raw_token}) do
    case Accounts.verify_login_token(raw_token) do
      {:ok, user} ->
        conn
        |> clear_session()
        |> put_session(:user_id, user.id)
        |> put_session(:authenticated_at, System.system_time(:second))
        |> configure_session(renew: true)
        |> put_flash(:info, "Welcome back!")
        |> redirect(to: ~p"/")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Invalid or expired login link. Please try again.")
        |> redirect(to: ~p"/login")
    end
  end

  def callback(conn, _params) do
    conn
    |> put_flash(:error, "Invalid or expired login link. Please try again.")
    |> redirect(to: ~p"/login")
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> configure_session(drop: true)
    |> redirect(to: ~p"/login")
  end
end

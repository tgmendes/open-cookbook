defmodule CookbookWeb.AuthController do
  use CookbookWeb, :controller

  alias Cookbook.Accounts

  def callback(conn, %{"token" => raw_token}) do
    case Accounts.verify_login_token(raw_token) do
      {:ok, user} ->
        conn
        |> put_session(:user_id, user.id)
        |> configure_session(renew: true)
        |> put_flash(:info, "Welcome back!")
        |> redirect(to: ~p"/")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Invalid or expired login link. Please try again.")
        |> redirect(to: ~p"/login")
    end
  end

  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: ~p"/login")
  end
end

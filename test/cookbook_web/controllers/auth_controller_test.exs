defmodule CookbookWeb.AuthControllerTest do
  use CookbookWeb.ConnCase, async: true

  alias Cookbook.Accounts

  @allowed_email "test@example.com"

  describe "GET /auth/callback" do
    test "logs in with a valid token", %{conn: conn} do
      {:ok, user} = Accounts.get_or_create_user_by_email(@allowed_email)
      {:ok, raw_token} = Accounts.create_login_token(user)

      conn = get(conn, ~p"/auth/callback?token=#{raw_token}")

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_id) == user.id
    end

    test "redirects to login with an invalid token", %{conn: conn} do
      conn = get(conn, ~p"/auth/callback?token=bogus-token")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid or expired"
    end
  end

  describe "GET /auth/logout" do
    test "clears session and redirects to login", %{conn: conn} do
      {:ok, user} = Accounts.get_or_create_user_by_email(@allowed_email)

      conn =
        conn
        |> init_test_session(%{user_id: user.id})
        |> get(~p"/auth/logout")

      assert redirected_to(conn) == ~p"/login"
    end
  end
end

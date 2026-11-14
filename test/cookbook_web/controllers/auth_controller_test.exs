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
      assert is_integer(get_session(conn, :authenticated_at))
    end

    test "redirects to login with an invalid token", %{conn: conn} do
      conn = get(conn, ~p"/auth/callback?token=bogus-token")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid or expired"
    end

    test "missing callback parameters redirect safely", %{conn: conn} do
      assert conn |> get(~p"/auth/callback") |> redirected_to() == ~p"/login"
    end

    test "login discards unrelated session values", %{conn: conn} do
      {:ok, user} = Accounts.get_or_create_user_by_email(@allowed_email)
      {:ok, token} = Accounts.create_login_token(user)

      conn =
        conn |> init_test_session(%{untrusted: "value"}) |> get(~p"/auth/callback?token=#{token}")

      refute get_session(conn, :untrusted)
    end
  end

  describe "DELETE /auth/logout" do
    test "requires CSRF protection", %{conn: conn} do
      assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
        conn |> put_private(:plug_skip_csrf_protection, false) |> delete(~p"/auth/logout")
      end
    end

    test "clears session and redirects to login", %{conn: conn} do
      {:ok, user} = Accounts.get_or_create_user_by_email(@allowed_email)

      conn =
        conn
        |> init_test_session(%{user_id: user.id, authenticated_at: System.system_time(:second)})
        |> delete(~p"/auth/logout")

      assert redirected_to(conn) == ~p"/login"
      assert conn |> recycle() |> get("/") |> redirected_to() == "/login"
    end
  end
end

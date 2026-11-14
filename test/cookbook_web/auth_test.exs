defmodule CookbookWeb.AuthTest do
  use CookbookWeb.ConnCase, async: true
  alias Cookbook.Accounts

  test "an expired browser session cannot access the dashboard", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")

    conn =
      conn
      |> init_test_session(%{
        user_id: user.id,
        authenticated_at: System.system_time(:second) - 31 * 86_400
      })
      |> get("/")

    assert redirected_to(conn) == "/login"
  end

  test "a legacy session without an authentication timestamp must sign in again", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")
    conn = conn |> init_test_session(%{user_id: user.id}) |> get("/")
    assert redirected_to(conn) == "/login"
  end

  test "a removed owner cannot use an existing session", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")
    user |> Ecto.Changeset.change(email: "removed@example.com") |> Cookbook.Repo.update!()

    conn =
      conn
      |> init_test_session(%{user_id: user.id, authenticated_at: System.system_time(:second)})
      |> get("/")

    assert redirected_to(conn) == "/login"
  end
end

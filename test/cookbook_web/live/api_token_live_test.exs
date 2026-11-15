defmodule CookbookWeb.ApiTokenLiveTest do
  use CookbookWeb.ConnCase, async: true
  import Phoenix.LiveViewTest
  alias Cookbook.Accounts

  test "anonymous visitors must sign in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, "/settings/connections")
  end

  test "owner creates, dismisses, and revokes a token", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")

    conn =
      init_test_session(conn, %{user_id: user.id, authenticated_at: System.system_time(:second)})

    {:ok, view, _} = live(conn, "/settings/connections")
    view |> form("#api-token-form", token: %{name: "Claude"}) |> render_submit()
    assert has_element?(view, "#new-api-token")
    [%{id: id}] = Accounts.list_api_tokens(user)
    assert has_element?(view, "#api-token-#{id}")
    view |> element("#dismiss-api-token") |> render_click()
    refute has_element?(view, "#new-api-token")
    view |> element("#revoke-api-token-#{id}") |> render_click()
    assert [%{revoked_at: revoked}] = Accounts.list_api_tokens(user)
    assert revoked
    {:ok, revisited, _} = live(conn, "/settings/connections")
    refute has_element?(revisited, "#new-api-token")
    assert "no-store" in get_resp_header(get(conn, "/settings/connections"), "cache-control")
  end

  test "invalid names do not issue a token", %{conn: conn} do
    {:ok, user} = Accounts.get_or_create_user_by_email("test@example.com")

    conn =
      init_test_session(conn, %{user_id: user.id, authenticated_at: System.system_time(:second)})

    {:ok, view, _} = live(conn, "/settings/connections")
    view |> form("#api-token-form", token: %{name: ""}) |> render_submit()
    assert has_element?(view, "#api-token-error")
    assert [] == Accounts.list_api_tokens(user)
  end
end

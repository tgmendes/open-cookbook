defmodule CookbookWeb.LoginLiveTest do
  use CookbookWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  test "delivery failure leaves the form available with an error", %{conn: conn} do
    original = Application.get_env(:cookbook, Cookbook.Mailer)
    Application.put_env(:cookbook, Cookbook.Mailer, adapter: Cookbook.FailingMailAdapter)
    on_exit(fn -> Application.put_env(:cookbook, Cookbook.Mailer, original) end)

    {:ok, view, _} = live(conn, "/login")
    view |> form("#login_form", login: %{email: "test@example.com"}) |> render_submit()
    assert has_element?(view, "#login-error")
    assert has_element?(view, "#login_form")
    refute has_element?(view, "#login-sent")
  end

  test "unauthorized email receives the same generic sent state", %{conn: conn} do
    {:ok, view, _} = live(conn, "/login")
    view |> form("#login_form", login: %{email: "other@example.com"}) |> render_submit()
    assert has_element?(view, "#login-sent")
  end
end

defmodule CookbookWeb.Auth do
  @moduledoc "Authentication shared by browser requests and LiveView connections."
  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]
  use CookbookWeb, :verified_routes
  alias Cookbook.Accounts

  @session_lifetime 30 * 86_400

  def session_user(session) do
    timestamp = session["authenticated_at"]
    now = System.system_time(:second)

    with true <-
           is_integer(timestamp) and timestamp <= now and now - timestamp < @session_lifetime,
         user when not is_nil(user) <- Accounts.get_user(session["user_id"]),
         true <- Accounts.authorized_user?(user) do
      user
    else
      _ -> nil
    end
  end

  def on_mount(:require_auth, _params, session, socket) do
    case session_user(session) do
      nil ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}

      user ->
        socket =
          socket
          |> assign(
            current_user: user,
            current_scope: %{user: user},
            navigation: Cookbook.Planner.navigation_summary(user.id)
          )
          |> attach_hook(:check_authentication, :handle_event, fn _, _, socket ->
            if session_user(session) do
              {:cont, socket}
            else
              {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
            end
          end)
          |> attach_hook(:set_nav_path, :handle_params, fn _, uri, socket ->
            if session_user(session) do
              {:cont, assign(socket, :nav_path, URI.parse(uri).path)}
            else
              {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}
            end
          end)
          |> attach_hook(:toggle_unit_system, :handle_event, fn
            "toggle_unit_system", _, socket ->
              current = socket.assigns.current_user
              system = if current.unit_system == "metric", do: "imperial", else: "metric"

              case Accounts.update_user_unit_system(current, system) do
                {:ok, user} ->
                  {:halt, assign(socket, current_user: user, current_scope: %{user: user})}

                {:error, _} ->
                  {:halt, socket}
              end

            _, _, socket ->
              {:cont, socket}
          end)

        {:cont, socket}
    end
  end

  def on_mount(:maybe_auth, _params, session, socket) do
    user = session_user(session)
    {:cont, assign(socket, current_user: user, current_scope: if(user, do: %{user: user}))}
  end

  def fetch_current_user(conn, _opts) do
    user = session_user(Plug.Conn.get_session(conn))

    conn
    |> Plug.Conn.assign(:current_user, user)
    |> Plug.Conn.assign(:current_scope, if(user, do: %{user: user}))
  end

  def no_store(conn, _opts), do: Plug.Conn.put_resp_header(conn, "cache-control", "no-store")

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> Plug.Conn.clear_session()
      |> Phoenix.Controller.redirect(to: ~p"/login")
      |> Plug.Conn.halt()
    end
  end
end

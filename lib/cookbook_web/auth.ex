defmodule CookbookWeb.Auth do
  @moduledoc """
  Authentication helpers for LiveView and controllers.
  Provides on_mount hooks and session helpers.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [attach_hook: 4]
  use CookbookWeb, :verified_routes

  alias Cookbook.Accounts

  @doc """
  LiveView on_mount hook that requires authentication.
  Redirects to /login if no user is in session.
  """
  def on_mount(:require_auth, _params, session, socket) do
    case session["user_id"] do
      nil ->
        {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}

      user_id ->
        case Accounts.get_user(user_id) do
          nil ->
            {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/login")}

          user ->
            socket =
              socket
              |> assign(current_user: user)
              |> attach_hook(:set_nav_path, :handle_params, fn _params, uri, socket ->
                {:cont, assign(socket, :nav_path, URI.parse(uri).path)}
              end)

            {:cont, socket}
        end
    end
  end

  def on_mount(:maybe_auth, _params, session, socket) do
    case session["user_id"] do
      nil ->
        {:cont, assign(socket, current_user: nil)}

      user_id ->
        {:cont, assign(socket, current_user: Accounts.get_user(user_id))}
    end
  end

  @doc """
  Plug that loads the current user from session into conn assigns.
  """
  def fetch_current_user(conn, _opts) do
    user_id = Plug.Conn.get_session(conn, :user_id)

    if user_id do
      user = Accounts.get_user(user_id)
      Plug.Conn.assign(conn, :current_user, user)
    else
      Plug.Conn.assign(conn, :current_user, nil)
    end
  end

  @doc """
  Plug that requires the user to be authenticated.
  Redirects to /login if not.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> Phoenix.Controller.redirect(to: ~p"/login")
      |> Plug.Conn.halt()
    end
  end
end

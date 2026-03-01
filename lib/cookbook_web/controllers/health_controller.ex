defmodule CookbookWeb.HealthController do
  use CookbookWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end

defmodule CookbookWeb.OpenAPIController do
  use CookbookWeb, :controller
  def show(conn, _params), do: json(conn, CookbookWeb.OpenAPI.spec())
end

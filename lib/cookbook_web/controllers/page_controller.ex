defmodule CookbookWeb.PageController do
  use CookbookWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

defmodule CookbookWeb.ApiFallbackController do
  use CookbookWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    details = Ecto.Changeset.traverse_errors(changeset, fn {message, _} -> message end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: "validation_error", details: details}})
  end

  def call(conn, {:error, reason}) do
    {status, code} =
      case reason do
        :not_found -> {:not_found, "not_found"}
        :conflict -> {:conflict, "conflict"}
        :storage_unavailable -> {:service_unavailable, "storage_unavailable"}
        _ -> {:unprocessable_entity, "validation_error"}
      end

    conn |> put_status(status) |> json(%{error: %{code: code}})
  end
end

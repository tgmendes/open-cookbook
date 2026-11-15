defmodule Cookbook.ApiRequests do
  @moduledoc "Owner-scoped, transactional replay protection for recipe creation."
  import Ecto.Query
  alias Cookbook.{Repo, ApiRequest}
  alias Cookbook.Accounts.User

  def run(user_id, key, body, create) do
    fingerprint = :crypto.hash(:sha256, :erlang.term_to_binary(body, [:deterministic]))
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      # Serialize the claim and recipe insert together, including concurrent first requests.
      Repo.one!(from u in User, where: u.id == ^user_id, lock: "FOR UPDATE")

      from(r in ApiRequest, where: r.user_id == ^user_id and r.expires_at <= ^now)
      |> Repo.delete_all()

      case Repo.get_by(ApiRequest, user_id: user_id, key: key) do
        %ApiRequest{fingerprint: ^fingerprint, response: response} ->
          response

        %ApiRequest{} ->
          Repo.rollback(:conflict)

        nil ->
          case create.() do
            {:ok, response} ->
              response = response |> Jason.encode!() |> Jason.decode!()

              Repo.insert!(%ApiRequest{
                user_id: user_id,
                key: key,
                fingerprint: fingerprint,
                response: response,
                expires_at: DateTime.add(now, 86_400, :second)
              })

              response

            {:error, reason} ->
              Repo.rollback(reason)
          end
      end
    end)
  end
end

defmodule Cookbook.Accounts do
  @moduledoc """
  The Accounts context. Handles user management and magic-link authentication.
  """

  import Ecto.Query
  alias Cookbook.Repo
  alias Cookbook.Accounts.{User, LoginToken, ApiToken}

  @token_validity_minutes 10

  @doc """
  Gets or creates a user by email, but only if the email matches the allowed email.
  Returns `{:ok, user}` or `{:error, :unauthorized}`.
  """
  def get_or_create_user_by_email(email) when is_binary(email) do
    email = String.downcase(String.trim(email))

    if email_allowed?(email) do
      case Repo.get_by(User, email: email) do
        nil ->
          %User{}
          |> User.changeset(%{email: email})
          |> Repo.insert(on_conflict: :nothing, conflict_target: :email)
          |> case do
            {:ok, _} -> {:ok, Repo.get_by!(User, email: email)}
            error -> error
          end

        user ->
          {:ok, user}
      end
    else
      {:error, :unauthorized}
    end
  end

  def get_or_create_user_by_email(_), do: {:error, :unauthorized}

  @doc "Requests a magic link with an owner-scoped one-minute delivery cooldown."
  def request_login_token(email) do
    with {:ok, user} <- get_or_create_user_by_email(email) do
      Repo.transaction(fn ->
        Repo.one!(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE")
        cutoff = DateTime.utc_now() |> DateTime.add((@token_validity_minutes - 1) * 60, :second)

        recent? =
          Repo.exists?(
            from token in LoginToken,
              where: token.user_id == ^user.id and token.expires_at > ^cutoff
          )

        if recent?, do: Repo.rollback(:rate_limited)

        case create_login_token(user) do
          {:ok, raw} -> {user, raw}
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, {user, raw}} -> {:ok, user, raw}
        error -> error
      end
    end
  end

  @doc """
  Gets a user by id. Returns nil if not found.
  """
  def get_user(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(User, id)
      :error -> nil
    end
  end

  def authorized_user?(%User{email: email}), do: email_allowed?(email)
  def authorized_user?(_), do: false

  @doc """
  Creates a login token for a user. Returns `{:ok, raw_token}` where
  `raw_token` is the unhashed token to be sent in the magic link.
  The hashed version is stored in the database.
  """
  def create_login_token(%User{} = user) do
    raw_token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    hashed_token = hash_token(raw_token)

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(@token_validity_minutes * 60, :second)
      |> DateTime.truncate(:second)

    result =
      %LoginToken{user_id: user.id}
      |> LoginToken.changeset(%{
        token: hashed_token,
        expires_at: expires_at
      })
      |> Repo.insert()

    case result do
      {:ok, _token} -> {:ok, raw_token}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Verifies a raw login token. If valid and unused, marks it as used and
  returns `{:ok, user}`. Otherwise returns `{:error, reason}`.
  """
  def verify_login_token(raw_token) when is_binary(raw_token) and byte_size(raw_token) == 43 do
    hashed_token = hash_token(raw_token)
    now = DateTime.utc_now()

    query =
      from lt in LoginToken,
        where: lt.token == ^hashed_token,
        where: is_nil(lt.used_at),
        where: lt.expires_at > ^now,
        join: user in assoc(lt, :user),
        where: user.email == ^normalized_allowed_email(),
        select: lt.user_id

    case Repo.update_all(query, set: [used_at: DateTime.truncate(now, :second)]) do
      {1, [user_id]} -> {:ok, get_user(user_id)}
      _ -> {:error, :invalid_token}
    end
  end

  def verify_login_token(_), do: {:error, :invalid_token}

  def create_api_token(%User{} = user, name) when is_binary(name) do
    if authorized_user?(get_user(user.id)) do
      raw = "ocb_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      %ApiToken{
        user_id: user.id,
        token_hash: :crypto.hash(:sha256, raw),
        expires_at:
          DateTime.utc_now() |> DateTime.add(90 * 86_400, :second) |> DateTime.truncate(:second)
      }
      |> ApiToken.changeset(%{name: String.trim(name)})
      |> Repo.insert()
      |> case do
        {:ok, record} -> {:ok, token_metadata(record), raw}
        {:error, changeset} -> {:error, changeset}
      end
    else
      {:error, :unauthorized}
    end
  end

  def create_api_token(_, _), do: {:error, :invalid_name}

  def authenticate_api_token("ocb_" <> _ = raw) when byte_size(raw) == 47 do
    hash = :crypto.hash(:sha256, raw)
    now = DateTime.utc_now()

    user =
      from(token in ApiToken,
        join: user in assoc(token, :user),
        where: token.token_hash == ^hash and is_nil(token.revoked_at) and token.expires_at > ^now,
        select: user
      )
      |> Repo.one()

    if authorized_user?(user), do: {:ok, user}, else: {:error, :unauthorized}
  end

  def authenticate_api_token(_), do: {:error, :unauthorized}

  def list_api_tokens(%User{id: id}) do
    from(token in ApiToken, where: token.user_id == ^id, order_by: [desc: token.inserted_at])
    |> Repo.all()
    |> Enum.map(&token_metadata/1)
  end

  def revoke_api_token(%User{id: user_id}, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %ApiToken{} = token <- Repo.get_by(ApiToken, id: id, user_id: user_id) do
      token
      |> Ecto.Changeset.change(
        revoked_at: token.revoked_at || DateTime.truncate(DateTime.utc_now(), :second)
      )
      |> Repo.update!()

      :ok
    else
      _ -> {:error, :not_found}
    end
  end

  defp token_metadata(record),
    do: Map.take(record, [:id, :name, :expires_at, :revoked_at, :inserted_at])

  defp hash_token(raw_token) do
    :crypto.hash(:sha256, raw_token) |> Base.encode64()
  end

  def update_user_unit_system(%User{} = user, unit_system) do
    user
    |> User.unit_system_changeset(%{unit_system: unit_system})
    |> Repo.update()
  end

  defp email_allowed?(email) do
    allowed = allowed_email()

    is_binary(email) and is_binary(allowed) and String.trim(allowed) != "" and
      String.downcase(String.trim(allowed)) == email
  end

  defp allowed_email do
    Application.get_env(:cookbook, :allowed_email)
  end

  defp normalized_allowed_email do
    case allowed_email() do
      email when is_binary(email) -> String.downcase(String.trim(email))
      _ -> ""
    end
  end
end

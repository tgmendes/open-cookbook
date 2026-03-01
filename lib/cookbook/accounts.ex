defmodule Cookbook.Accounts do
  @moduledoc """
  The Accounts context. Handles user management and magic-link authentication.
  """

  import Ecto.Query
  alias Cookbook.Repo
  alias Cookbook.Accounts.{User, LoginToken}

  @token_validity_minutes 10

  @doc """
  Gets or creates a user by email, but only if the email matches the allowed email.
  Returns `{:ok, user}` or `{:error, :unauthorized}`.
  """
  def get_or_create_user_by_email(email) do
    email = String.downcase(String.trim(email))

    if email_allowed?(email) do
      case Repo.get_by(User, email: email) do
        nil ->
          %User{}
          |> User.changeset(%{email: email})
          |> Repo.insert()

        user ->
          {:ok, user}
      end
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Gets a user by id. Returns nil if not found.
  """
  def get_user(id), do: Repo.get(User, id)

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
      %LoginToken{}
      |> LoginToken.changeset(%{
        token: hashed_token,
        user_id: user.id,
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
  def verify_login_token(raw_token) do
    hashed_token = hash_token(raw_token)
    now = DateTime.utc_now()

    query =
      from lt in LoginToken,
        where: lt.token == ^hashed_token,
        where: is_nil(lt.used_at),
        where: lt.expires_at > ^now,
        preload: [:user]

    case Repo.one(query) do
      nil ->
        {:error, :invalid_token}

      login_token ->
        login_token
        |> Ecto.Changeset.change(used_at: DateTime.truncate(now, :second))
        |> Repo.update()

        {:ok, login_token.user}
    end
  end

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
    allowed != nil && String.downcase(String.trim(allowed)) == email
  end

  defp allowed_email do
    Application.get_env(:cookbook, :allowed_email)
  end
end

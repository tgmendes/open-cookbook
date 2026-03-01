defmodule Cookbook.Accounts.LoginToken do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "login_tokens" do
    field :token, :string
    field :expires_at, :utc_datetime
    field :used_at, :utc_datetime

    belongs_to :user, Cookbook.Accounts.User
  end

  def changeset(login_token, attrs) do
    login_token
    |> cast(attrs, [:token, :expires_at, :user_id])
    |> validate_required([:token, :expires_at, :user_id])
    |> unique_constraint(:token)
    |> foreign_key_constraint(:user_id)
  end
end

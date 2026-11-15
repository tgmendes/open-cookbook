defmodule Cookbook.Accounts.ApiToken do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "api_tokens" do
    field :name, :string
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime
    belongs_to :user, Cookbook.Accounts.User
    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 100)
    |> unique_constraint(:token_hash)
    |> foreign_key_constraint(:user_id)
  end
end

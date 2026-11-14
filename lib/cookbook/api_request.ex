defmodule Cookbook.ApiRequest do
  use Ecto.Schema
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "api_requests" do
    belongs_to :user, Cookbook.Accounts.User
    field :key, :string
    field :fingerprint, :binary
    field :response, :map
    field :expires_at, :utc_datetime
  end
end

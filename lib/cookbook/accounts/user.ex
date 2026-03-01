defmodule Cookbook.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users" do
    field :email, :string
    field :unit_system, :string, default: "metric"

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must have the @ sign and no spaces")
    |> unique_constraint(:email)
  end

  def unit_system_changeset(user, attrs) do
    user
    |> cast(attrs, [:unit_system])
    |> validate_inclusion(:unit_system, ["metric", "imperial"])
  end
end

defmodule Cookbook.Repo.Migrations.CreateLoginTokens do
  use Ecto.Migration

  def change do
    create table(:login_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :used_at, :utc_datetime
    end

    create unique_index(:login_tokens, [:token])
    create index(:login_tokens, [:user_id])
  end
end

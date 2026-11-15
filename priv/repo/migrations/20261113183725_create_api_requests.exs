defmodule Cookbook.Repo.Migrations.CreateApiRequests do
  use Ecto.Migration

  def change do
    create table(:api_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :key, :string, null: false
      add :fingerprint, :binary, null: false
      add :response, :map, null: false
      add :expires_at, :utc_datetime, null: false
    end

    create unique_index(:api_requests, [:user_id, :key])
    create index(:api_requests, [:expires_at])
  end
end

defmodule Cookbook.Repo.Migrations.AddUnitSystemToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :unit_system, :string, default: "metric", null: false
    end
  end
end

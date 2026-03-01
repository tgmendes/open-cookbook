defmodule Cookbook.Repo.Migrations.CreateSteps do
  use Ecto.Migration

  def change do
    create table(:steps, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :recipe_id, references(:recipes, type: :binary_id, on_delete: :delete_all), null: false
      add :position, :integer, null: false, default: 0
      add :instruction, :text, null: false
      add :duration_minutes, :integer
    end

    create index(:steps, [:recipe_id])
  end
end

defmodule Cookbook.Repo.Migrations.CreateIngredients do
  use Ecto.Migration

  def change do
    create table(:ingredients, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :recipe_id, references(:recipes, type: :binary_id, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :quantity, :string
      add :unit, :string
      add :group_name, :string
      add :position, :integer, null: false, default: 0
    end

    create index(:ingredients, [:recipe_id])
  end
end

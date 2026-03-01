defmodule Cookbook.Repo.Migrations.CreateRecipes do
  use Ecto.Migration

  def change do
    execute "CREATE TYPE source_type AS ENUM ('manual', 'scraped', 'generated')", "DROP TYPE source_type"

    create table(:recipes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :description, :text
      add :servings, :integer
      add :prep_time_minutes, :integer
      add :cook_time_minutes, :integer
      add :total_time_minutes, :integer
      add :source_url, :string
      add :source_type, :source_type, null: false, default: "manual"
      add :tags, {:array, :string}, default: []
      add :image_url, :string
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:recipes, [:user_id])
    create index(:recipes, [:tags], using: :gin)
  end
end

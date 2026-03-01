defmodule Cookbook.Repo.Migrations.CreateMealPlans do
  use Ecto.Migration

  def change do
    execute "CREATE TYPE meal_type AS ENUM ('lunch', 'dinner')", "DROP TYPE meal_type"

    create table(:meal_plans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :week_start, :date, null: false
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:meal_plans, [:user_id, :week_start])

    create table(:meal_plan_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :meal_plan_id, references(:meal_plans, type: :binary_id, on_delete: :delete_all), null: false
      add :recipe_id, references(:recipes, type: :binary_id, on_delete: :delete_all), null: false
      add :day_of_week, :integer, null: false
      add :meal_type, :meal_type, null: false
      add :position, :integer, null: false, default: 0
    end

    create unique_index(:meal_plan_entries, [:meal_plan_id, :day_of_week, :meal_type, :position])
    create index(:meal_plan_entries, [:meal_plan_id])
  end
end

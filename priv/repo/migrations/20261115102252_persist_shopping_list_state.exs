defmodule Cookbook.Repo.Migrations.PersistShoppingListState do
  use Ecto.Migration

  def change do
    alter table(:meal_plans) do
      add :shopping_checked, {:array, :string}, default: [], null: false
      add :shopping_extras, {:array, :string}, default: [], null: false
    end
  end
end

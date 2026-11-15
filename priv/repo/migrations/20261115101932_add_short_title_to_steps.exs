defmodule Cookbook.Repo.Migrations.AddShortTitleToSteps do
  use Ecto.Migration

  def change do
    alter table(:steps) do
      add :short_title, :string
    end
  end
end

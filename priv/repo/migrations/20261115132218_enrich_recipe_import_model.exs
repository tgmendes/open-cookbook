defmodule Cookbook.Repo.Migrations.EnrichRecipeImportModel do
  use Ecto.Migration

  def change do
    alter table(:recipes) do
      add :prep_ahead, :text
      add :troubleshooting, :text
      add :variations, :text
      add :freezer_friendly, :boolean, null: false, default: false
      add :freezer_notes, :text
      add :source_conversation_url, :text
      add :image_credit, :text
      add :image_source_url, :text
      add :image_license, :text
      add :image_match, :string
    end

    alter table(:ingredients) do
      add :ref, :string
      add :quantity_value, :decimal
      add :quantity_text, :text
    end

    alter table(:steps) do
      add :ingredient_refs, {:array, :string}, null: false, default: []
    end

    flush()
    execute("UPDATE ingredients SET ref = id::text, quantity_text = quantity", "SELECT 1")

    execute(
      """
      UPDATE ingredients SET quantity_value = CASE
        WHEN trim(quantity) ~ '^[0-9]+(\\.[0-9]+)?$' THEN trim(quantity)::numeric
        WHEN trim(quantity) ~ '^[0-9]+/[0-9]+$' THEN
          split_part(trim(quantity), '/', 1)::numeric / nullif(split_part(trim(quantity), '/', 2)::numeric, 0)
        WHEN trim(quantity) ~ '^[0-9]+[[:space:]]+[0-9]+/[0-9]+$' THEN
          split_part(regexp_replace(trim(quantity), '[[:space:]]+', ' '), ' ', 1)::numeric +
          split_part(split_part(regexp_replace(trim(quantity), '[[:space:]]+', ' '), ' ', 2), '/', 1)::numeric /
          nullif(split_part(trim(quantity), '/', 2)::numeric, 0)
        ELSE NULL END
      """,
      "SELECT 1"
    )

    create unique_index(:ingredients, [:recipe_id, :ref])
    create constraint(:ingredients, :quantity_value_nonnegative, check: "quantity_value >= 0")
  end
end

defmodule Cookbook.Recipes.Recipe do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "recipes" do
    field :title, :string
    field :description, :string
    field :servings, :integer
    field :prep_time_minutes, :integer
    field :cook_time_minutes, :integer
    field :total_time_minutes, :integer
    field :source_url, :string
    field :source_type, Ecto.Enum, values: [:manual, :scraped, :generated], default: :manual
    field :tags, {:array, :string}, default: []
    field :image_url, :string
    field :notes, :string
    field :prep_ahead, :string
    field :troubleshooting, :string
    field :variations, :string
    field :freezer_friendly, :boolean, default: false
    field :freezer_notes, :string
    field :source_conversation_url, :string
    field :image_credit, :string
    field :image_source_url, :string
    field :image_license, :string
    field :image_match, Ecto.Enum, values: [:exact, :approximate]

    belongs_to :user, Cookbook.Accounts.User

    has_many :ingredients, Cookbook.Recipes.Ingredient,
      on_replace: :delete,
      preload_order: [asc: :position]

    has_many :steps, Cookbook.Recipes.Step, on_replace: :delete, preload_order: [asc: :position]

    timestamps(type: :utc_datetime)
  end

  def changeset(recipe, attrs) do
    attrs = position_arrays(attrs)

    recipe
    |> cast(attrs, [
      :title,
      :description,
      :servings,
      :prep_time_minutes,
      :cook_time_minutes,
      :source_url,
      :source_type,
      :tags,
      :image_url,
      :notes,
      :prep_ahead,
      :troubleshooting,
      :variations,
      :freezer_friendly,
      :freezer_notes,
      :source_conversation_url,
      :image_credit,
      :image_source_url,
      :image_license,
      :image_match
    ])
    |> validate_required([:title, :user_id])
    |> validate_length(:title, max: 255)
    |> validate_length(:image_url, max: 255)
    |> validate_length(:source_url, max: 255)
    |> validate_number(:servings, greater_than: 0)
    |> validate_number(:prep_time_minutes, greater_than_or_equal_to: 0)
    |> validate_number(:cook_time_minutes, greater_than_or_equal_to: 0)
    |> validate_change(:source_url, &validate_web_url/2)
    |> validate_change(:image_url, &validate_web_url/2)
    |> validate_change(:image_source_url, &validate_web_url/2)
    |> validate_change(:source_conversation_url, &validate_web_url/2)
    |> validate_required([:freezer_friendly])
    |> compute_total_time()
    |> cast_assoc(:ingredients,
      with: &Cookbook.Recipes.Ingredient.changeset/2,
      sort_param: :ingredients_sort,
      drop_param: :ingredients_drop
    )
    |> cast_assoc(:steps,
      with: &Cookbook.Recipes.Step.changeset/2,
      sort_param: :steps_sort,
      drop_param: :steps_drop
    )
    |> foreign_key_constraint(:user_id)
    |> validate_ingredient_refs()
  end

  defp position_arrays(attrs) do
    Enum.reduce([:ingredients, :steps], attrs, fn collection, attrs ->
      key = if Map.has_key?(attrs, collection), do: collection, else: Atom.to_string(collection)

      case Map.get(attrs, key) do
        items when is_list(items) ->
          Map.put(
            attrs,
            key,
            Enum.with_index(items, fn item, index ->
              position = if Enum.any?(Map.keys(item), &is_atom/1), do: :position, else: "position"
              Map.put(item, position, index)
            end)
          )

        _ ->
          attrs
      end
    end)
  end

  defp validate_ingredient_refs(changeset) do
    ingredients = get_field(changeset, :ingredients) || []
    steps = get_field(changeset, :steps) || []
    refs = Enum.map(ingredients, & &1.ref)

    changeset =
      if length(refs) == length(Enum.uniq(refs)),
        do: changeset,
        else: add_error(changeset, :ingredients, "references must be unique within a recipe")

    valid? =
      Enum.all?(steps, fn step ->
        linked = step.ingredient_refs || []

        tokens =
          Regex.scan(~r/\{\{([a-zA-Z0-9_-]+)\}\}/, step.instruction || "",
            capture: :all_but_first
          )
          |> List.flatten()

        Enum.all?(linked, &(&1 in refs)) and Enum.all?(tokens, &(&1 in linked))
      end)

    if valid?,
      do: changeset,
      else:
        add_error(
          changeset,
          :steps,
          "ingredient references must exist in this recipe; inline placeholders must also be listed in ingredient_refs"
        )
  end

  defp validate_web_url(field, value) do
    uri = URI.parse(value)

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" and
         is_nil(uri.userinfo),
       do: [],
       else: [{field, "must be an HTTP or HTTPS URL without credentials"}]
  end

  defp compute_total_time(changeset) do
    prep = get_field(changeset, :prep_time_minutes)
    cook = get_field(changeset, :cook_time_minutes)

    total =
      case {prep, cook} do
        {nil, nil} -> nil
        {p, nil} -> p
        {nil, c} -> c
        {p, c} -> p + c
      end

    put_change(changeset, :total_time_minutes, total)
  end
end

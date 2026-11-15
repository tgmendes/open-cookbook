defmodule CookbookWeb.RecipeFormLive do
  use CookbookWeb, :live_view
  alias Cookbook.Recipes
  alias Cookbook.Recipes.{Recipe, Ingredient}

  def mount(params, _session, socket) do
    recipe =
      case params do
        %{"id" => id} -> Recipes.get_recipe!(socket.assigns.current_user.id, id)
        _ -> %Recipe{user_id: socket.assigns.current_user.id, ingredients: [], steps: []}
      end

    params = %{
      "tags_input" => Enum.join(recipe.tags || [], ", "),
      "ingredients" =>
        indexed(recipe.ingredients, [
          :id,
          :name,
          :quantity_value,
          :quantity_text,
          :ref,
          :unit,
          :group_name,
          :position
        ]),
      "steps" =>
        indexed(recipe.steps, [
          :id,
          :instruction,
          :short_title,
          :duration_minutes,
          :position,
          :ingredient_refs
        ])
    }

    {:ok,
     socket
     |> assign(
       recipe: recipe,
       recipe_params: params,
       page_title: if(recipe.id, do: "Edit recipe", else: "New recipe")
     )
     |> set_form(params), layout: false}
  end

  def handle_event("validate", %{"recipe" => params}, socket),
    do: {:noreply, set_form(socket, params, :validate)}

  def handle_event("save", %{"recipe" => params}, socket) do
    attrs = recipe_attrs(params)

    result =
      if socket.assigns.recipe.id do
        Recipes.update_recipe(socket.assigns.current_user.id, socket.assigns.recipe.id, attrs)
      else
        Recipes.create_recipe(socket.assigns.current_user.id, attrs)
      end

    case result do
      {:ok, recipe} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recipe saved.")
         |> push_navigate(to: ~p"/recipes/#{recipe.id}")}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> put_flash(:error, "This recipe is no longer available.")
         |> push_navigate(to: ~p"/recipes")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset), recipe_params: params)}
    end
  end

  def handle_event("add_ingredient", _, socket),
    do:
      add_item(socket, "ingredients", %{
        "name" => "",
        "quantity_value" => "",
        "quantity_text" => "",
        "ref" => Ecto.UUID.generate(),
        "unit" => ""
      })

  def handle_event("add_step", _, socket), do: add_item(socket, "steps", %{"instruction" => ""})

  def handle_event("remove_item", %{"collection" => collection, "index" => index}, socket)
      when collection in ["ingredients", "steps"] do
    items = socket.assigns.recipe_params |> Map.get(collection, %{}) |> Map.delete(index)
    {:noreply, set_form(socket, Map.put(socket.assigns.recipe_params, collection, items))}
  end

  defp add_item(socket, collection, item) do
    items = Map.get(socket.assigns.recipe_params, collection, %{})

    next =
      items
      |> Map.keys()
      |> Enum.map(&String.to_integer/1)
      |> Enum.max(fn -> -1 end)
      |> Kernel.+(1)

    params =
      Map.put(
        socket.assigns.recipe_params,
        collection,
        Map.put(items, to_string(next), Map.put(item, "position", next))
      )

    {:noreply, set_form(socket, params)}
  end

  defp set_form(socket, params, action \\ nil) do
    params = normalize_rows(params)

    changeset =
      socket.assigns.recipe
      |> Recipes.change_recipe(recipe_attrs(params))
      |> Map.put(:action, action)

    assign(socket, form: to_form(changeset), recipe_params: params)
  end

  defp recipe_attrs(params) do
    params = normalize_rows(params)

    tags =
      params
      |> Map.get("tags_input", "")
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    params
    |> Map.put("tags", tags)
    |> Map.put_new("ingredients", %{})
    |> Map.put_new("steps", %{})
  end

  defp normalize_rows(params) do
    Enum.reduce(["ingredients", "steps"], params, fn collection, params ->
      rows =
        params
        |> Map.get(collection, %{})
        |> Enum.sort_by(fn {key, _} -> String.to_integer(key) end)
        |> Enum.with_index(fn {_, attrs}, index ->
          attrs =
            if collection == "steps",
              do:
                Map.update(
                  attrs,
                  "ingredient_refs",
                  [],
                  &Enum.reject(&1, fn ref -> ref == "" end)
                ),
              else: attrs

          {to_string(index), Map.put(attrs, "position", index)}
        end)
        |> Map.new()

      Map.put(params, collection, rows)
    end)
  end

  defp indexed(items, fields) do
    items
    |> Enum.with_index(fn item, index ->
      {to_string(index),
       item |> Map.take(fields) |> Map.new(fn {key, value} -> {to_string(key), value} end)}
    end)
    |> Map.new()
  end

  def render(assigns) do
    assigns =
      assign(
        assigns,
        :ingredient_options,
        assigns.recipe_params["ingredients"]
        |> Enum.sort_by(fn {key, _} -> String.to_integer(key) end)
        |> Enum.map(fn {_, row} -> {row["name"] || "Ingredient", row["ref"]} end)
      )

    ~H"""
    <Layouts.app {assigns}>
      <div class="mx-auto max-w-3xl space-y-6">
        <header>
          <.link
            navigate="/recipes"
            class="inline-flex min-h-11 items-center gap-2 text-sm text-muted"
          >
            <.icon name="hero-arrow-left" class="size-4" />Back to recipes
          </.link>
          <h1 class="mt-1 text-4xl">{@page_title}</h1>
          <p class="mt-2 text-muted">
            Write a recipe here, or ask Claude to save one through your private connection.
          </p>
        </header>
        <.form for={@form} id="recipe-form" phx-change="validate" phx-submit="save" class="space-y-5">
          <section class="surface space-y-4 p-5 sm:p-6">
            <h2 class="text-xl">The recipe</h2>
            <.input field={@form[:title]} label="Title" required /><.input
              field={@form[:description]}
              type="textarea"
              label="Description"
            />
            <div class="grid gap-3 sm:grid-cols-3">
              <.input field={@form[:servings]} type="number" min="1" label="Servings" /><.input
                field={@form[:prep_time_minutes]}
                type="number"
                min="0"
                label="Prep time (min)"
              /><.input
                field={@form[:cook_time_minutes]}
                type="number"
                min="0"
                label="Cook time (min)"
              />
            </div>
          </section>
          <section class="surface space-y-4 p-5 sm:p-6">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <h2 class="text-xl">Ingredients</h2>
              <button id="add-ingredient" type="button" phx-click="add_ingredient" class="action">
                <.icon name="hero-plus" class="size-4" />Add ingredient
              </button>
            </div>
            <.inputs_for :let={ing} field={@form[:ingredients]}>
              <div id={"ingredient-row-#{ing.index}"} class="space-y-3 rounded-2xl bg-tag p-3">
                <.input field={ing[:ref]} type="hidden" />
                <.input
                  field={ing[:name]}
                  label={"Ingredient #{ing.index + 1}"}
                  placeholder="Ingredient name"
                />
                <div class="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)_44px] items-end gap-2">
                  <.input
                    field={ing[:quantity_value]}
                    type="number"
                    step="any"
                    min="0"
                    label="Quantity (number)"
                  /><.input
                    field={ing[:unit]}
                    type="select"
                    label="Unit"
                    options={Ingredient.unit_options(@current_user.unit_system)}
                  />
                  <button
                    id={"remove-ingredient-#{ing.index}"}
                    type="button"
                    phx-click="remove_item"
                    phx-value-collection="ingredients"
                    phx-value-index={ing.index}
                    aria-label="Remove ingredient"
                    class="action size-11 !p-0"
                  >
                    <.icon name="hero-trash" class="size-5" />
                  </button>
                </div>
                <.input
                  field={ing[:quantity_text]}
                  label="Display quantity (optional)"
                  placeholder="e.g. 1/2 or to taste"
                />
                <.input field={ing[:group_name]} label="Group (optional)" />
              </div>
            </.inputs_for>
          </section>
          <section class="surface space-y-4 p-5 sm:p-6">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <h2 class="text-xl">Method</h2>
              <button id="add-step" type="button" phx-click="add_step" class="action">
                <.icon name="hero-plus" class="size-4" />Add step
              </button>
            </div>
            <.inputs_for :let={step} field={@form[:steps]}>
              <div id={"step-row-#{step.index}"} class="space-y-3 rounded-2xl bg-tag p-4">
                <div class="flex items-center justify-between">
                  <h3 class="text-lg">Step {step.index + 1}</h3>
                  <button
                    id={"remove-step-#{step.index}"}
                    type="button"
                    phx-click="remove_item"
                    phx-value-collection="steps"
                    phx-value-index={step.index}
                    aria-label="Remove step"
                    class="action size-11 !p-0"
                  >
                    <.icon name="hero-trash" class="size-5" />
                  </button>
                </div>
                <.input
                  field={step[:short_title]}
                  label="Short title (optional)"
                  placeholder="e.g. Start the rice"
                /><.input field={step[:instruction]} type="textarea" label="Instructions" rows="3" /><.input
                  field={step[:duration_minutes]}
                  type="number"
                  min="0"
                  label="Timer (minutes, optional)"
                />
                <input type="hidden" name={step[:ingredient_refs].name <> "[]"} value="" />
                <.input
                  field={step[:ingredient_refs]}
                  type="select"
                  multiple
                  options={@ingredient_options}
                  label="Ingredients used in this step"
                />
              </div>
            </.inputs_for>
          </section>
          <section class="surface space-y-4 p-5 sm:p-6">
            <h2 class="text-xl">Kitchen advice</h2>
            <.input field={@form[:prep_ahead]} type="textarea" label="Prep ahead" />
            <.input field={@form[:freezer_friendly]} type="checkbox" label="Freezer friendly" />
            <.input field={@form[:freezer_notes]} type="textarea" label="Freezing & reheating" />
            <.input field={@form[:troubleshooting]} type="textarea" label="If it goes wrong" />
            <.input field={@form[:variations]} type="textarea" label="Swaps & scaling" />
          </section>
          <section class="surface space-y-4 p-5 sm:p-6">
            <h2 class="text-xl">Make it yours</h2>
            <.input
              name="recipe[tags_input]"
              value={@recipe_params["tags_input"] || ""}
              id="recipe-tags"
              label="Tags (separated by commas)"
              placeholder="vegetarian, quick, comfort"
            /><.input field={@form[:image_url]} type="url" label="Image URL" /><.input
              field={@form[:source_url]}
              type="url"
              label="Source URL"
            /><.input field={@form[:notes]} type="textarea" label="Other notes" />
            <.input field={@form[:source_conversation_url]} type="url" label="Source conversation" />
            <.input field={@form[:image_credit]} label="Photo credit" />
            <.input field={@form[:image_source_url]} type="url" label="Photo source" />
            <.input field={@form[:image_license]} label="Photo licence" />
            <.input
              field={@form[:image_match]}
              type="select"
              prompt="Not specified"
              options={[{"Exact recipe", :exact}, {"Approximate match", :approximate}]}
              label="Photo match"
            />
          </section>
          <div class="flex flex-wrap gap-3">
            <button
              id="save-recipe"
              type="submit"
              phx-disable-with="Saving…"
              class="action action-primary"
            >
              Save recipe <.icon name="hero-check" class="size-4" />
            </button>
            <.link
              navigate={if @recipe.id, do: ~p"/recipes/#{@recipe.id}", else: ~p"/recipes"}
              class="action"
            >Cancel</.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end

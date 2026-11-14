defmodule CookbookWeb.RecipeFormLive do
  use CookbookWeb, :live_view
  alias Cookbook.Recipes
  alias Cookbook.Recipes.Recipe

  def mount(params, _session, socket) do
    recipe =
      case params do
        %{"id" => id} -> Recipes.get_recipe!(socket.assigns.current_user.id, id)
        _ -> %Recipe{user_id: socket.assigns.current_user.id, ingredients: [], steps: []}
      end

    params = %{
      "tags_input" => Enum.join(recipe.tags || [], ", "),
      "ingredients" =>
        indexed(recipe.ingredients, [:id, :name, :quantity, :unit, :group_name, :position]),
      "steps" => indexed(recipe.steps, [:id, :instruction, :duration_minutes, :position])
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

  def handle_event("validate", %{"recipe" => params}, socket) do
    {:noreply, set_form(socket, params, :validate)}
  end

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
    do: add_item(socket, "ingredients", %{"name" => "", "quantity" => "", "unit" => ""})

  def handle_event("add_step", _, socket), do: add_item(socket, "steps", %{"instruction" => ""})

  def handle_event("remove_item", %{"collection" => collection, "index" => index}, socket)
      when collection in ["ingredients", "steps"] do
    items = socket.assigns.recipe_params |> Map.get(collection, %{}) |> Map.delete(index)
    params = Map.put(socket.assigns.recipe_params, collection, items)
    {:noreply, set_form(socket, params)}
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
          {to_string(index), Map.put(attrs, "position", index)}
        end)
        |> Map.new()

      Map.put(params, collection, rows)
    end)
  end

  defp indexed(items, fields) do
    items
    |> Enum.with_index(fn item, index ->
      attrs = item |> Map.take(fields) |> Map.new(fn {key, value} -> {to_string(key), value} end)
      {to_string(index), attrs}
    end)
    |> Map.new()
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_user={@current_user}
      nav_path={@nav_path}
    >
      <div class="mx-auto max-w-3xl space-y-6">
        <header>
          <.link navigate={~p"/recipes"} class="text-sm text-teal-700 hover:underline">
            ← Recipe catalog
          </.link>
          <h1 class="mt-3 text-3xl font-semibold tracking-tight">{@page_title}</h1>
          <p class="mt-2 text-sm text-base-content/60">
            Write a recipe here, or ask Claude to save one through your private connection.
          </p>
        </header>
        <.form for={@form} id="recipe-form" phx-change="validate" phx-submit="save" class="space-y-8">
          <section class="space-y-4 rounded-2xl border border-base-300/50 bg-base-100 p-6">
            <.input field={@form[:title]} label="Recipe title" required />
            <.input field={@form[:description]} type="textarea" label="Description" />
            <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
              <.input field={@form[:servings]} type="number" label="Servings" min="1" />
              <.input field={@form[:prep_time_minutes]} type="number" label="Prep (minutes)" min="0" />
              <.input field={@form[:cook_time_minutes]} type="number" label="Cook (minutes)" min="0" />
            </div>
            <.input
              name="recipe[tags_input]"
              id="recipe-tags"
              value={@recipe_params["tags_input"] || ""}
              label="Tags, separated by commas"
            />
          </section>
          <section class="space-y-4 rounded-2xl border border-base-300/50 bg-base-100 p-6">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold">Ingredients</h2>
              <button
                id="add-ingredient"
                type="button"
                phx-click="add_ingredient"
                class="rounded-lg px-3 py-2 text-sm font-medium text-teal-700 transition-colors hover:bg-teal-50"
              >
                + Add ingredient
              </button>
            </div>
            <.inputs_for :let={ingredient} field={@form[:ingredients]}>
              <div
                id={"ingredient-row-#{ingredient.index}"}
                class="grid grid-cols-2 items-end gap-3 border-t border-base-300/40 pt-4 sm:grid-cols-[2fr_1fr_1fr_auto]"
              >
                <.input field={ingredient[:name]} label="Ingredient" />
                <.input field={ingredient[:quantity]} label="Quantity" />
                <.input
                  field={ingredient[:unit]}
                  type="select"
                  label="Unit"
                  options={Cookbook.Recipes.Ingredient.unit_options(@current_user.unit_system)}
                />
                <button
                  id={"remove-ingredient-#{ingredient.index}"}
                  type="button"
                  phx-click="remove_item"
                  phx-value-collection="ingredients"
                  phx-value-index={ingredient.index}
                  aria-label="Remove ingredient"
                  class="mb-3 rounded-lg p-2 text-base-content/50 hover:bg-red-50 hover:text-red-700"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </div>
              <.input field={ingredient[:group_name]} label="Group (optional)" />
            </.inputs_for>
          </section>
          <section class="space-y-4 rounded-2xl border border-base-300/50 bg-base-100 p-6">
            <div class="flex items-center justify-between">
              <h2 class="text-lg font-semibold">Cooking steps</h2>
              <button
                id="add-step"
                type="button"
                phx-click="add_step"
                class="rounded-lg px-3 py-2 text-sm font-medium text-teal-700 transition-colors hover:bg-teal-50"
              >
                + Add step
              </button>
            </div>
            <.inputs_for :let={step} field={@form[:steps]}>
              <div id={"step-row-#{step.index}"} class="space-y-3 border-t border-base-300/40 pt-4">
                <div class="flex items-center justify-between">
                  <p class="text-xs font-semibold uppercase tracking-wider text-teal-700">
                    Step {step.index + 1}
                  </p>
                  <button
                    id={"remove-step-#{step.index}"}
                    type="button"
                    phx-click="remove_item"
                    phx-value-collection="steps"
                    phx-value-index={step.index}
                    aria-label="Remove step"
                    class="rounded-lg p-2 text-base-content/50 hover:bg-red-50 hover:text-red-700"
                  >
                    <.icon name="hero-x-mark" class="size-4" />
                  </button>
                </div>
                <.input field={step[:instruction]} type="textarea" label="Instruction" />
                <.input
                  field={step[:duration_minutes]}
                  type="number"
                  label="Timer (minutes, optional)"
                  min="0"
                />
              </div>
            </.inputs_for>
          </section>
          <section class="space-y-4 rounded-2xl border border-base-300/50 bg-base-100 p-6">
            <.input field={@form[:source_url]} type="url" label="Source URL (optional)" />
            <.input field={@form[:image_url]} type="url" label="Image URL (optional)" />
            <.input field={@form[:notes]} type="textarea" label="Notes" />
          </section>
          <div class="flex items-center gap-4 pb-8">
            <button
              id="save-recipe"
              type="submit"
              phx-disable-with="Saving…"
              class="rounded-xl bg-teal-700 px-6 py-3 text-sm font-semibold text-white transition-colors hover:bg-teal-800"
            >
              Save recipe
            </button>
            <.link navigate={~p"/recipes"} class="text-sm text-base-content/60 hover:underline">
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end

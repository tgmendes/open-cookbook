defmodule CookbookWeb.RecipeFormLive do
  use CookbookWeb, :live_view

  alias Cookbook.Recipes
  alias Cookbook.Recipes.Recipe

  def mount(params, _session, socket) do
    {recipe, action, page_title} =
      case params do
        %{"id" => id} ->
          recipe = Recipes.get_recipe!(id)
          {recipe, :edit, "Edit #{recipe.title}"}

        _ ->
          {%Recipe{
             user_id: socket.assigns.current_user.id,
             ingredients: [],
             steps: [],
             tags: []
           }, :new, "New Recipe"}
      end

    changeset = Recipes.change_recipe(recipe, %{})

    {:ok,
     assign(socket,
       recipe: recipe,
       action: action,
       page_title: page_title,
       form: to_form(changeset),
       tags_input: Enum.join(recipe.tags || [], ", "),
       tab: "manual",
       ai_url: "",
       ai_prompt: "",
       ai_loading: false
     )}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, tab: tab)}
  end

  def handle_event("import_url", %{"url" => url}, socket) do
    self_pid = self()

    Task.start(fn ->
      result = Cookbook.AI.scrape_recipe_from_url(url)
      send(self_pid, {:ai_result, result})
    end)

    {:noreply, assign(socket, ai_loading: true, ai_url: url)}
  end

  def handle_event("generate_recipe", %{"prompt" => prompt}, socket) do
    self_pid = self()

    Task.start(fn ->
      result = Cookbook.AI.generate_recipe(prompt)
      send(self_pid, {:ai_result, result})
    end)

    {:noreply, assign(socket, ai_loading: true, ai_prompt: prompt)}
  end

  def handle_event("validate", %{"recipe" => recipe_params}, socket) do
    recipe_params = process_tags(recipe_params, socket)

    changeset =
      socket.assigns.recipe
      |> Recipes.change_recipe(recipe_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"recipe" => recipe_params}, socket) do
    recipe_params = process_tags(recipe_params, socket)
    save_recipe(socket, socket.assigns.action, recipe_params)
  end

  def handle_event("add_ingredient", _params, socket) do
    changeset = socket.assigns.form.source
    ingredients = Ecto.Changeset.get_field(changeset, :ingredients) || []

    new_ingredient = %Cookbook.Recipes.Ingredient{position: length(ingredients)}
    updated = ingredients ++ [new_ingredient]

    changeset =
      socket.assigns.recipe
      |> Recipes.change_recipe(
        changeset.params
        |> Map.put("ingredients", build_nested_params(updated, &ingredient_to_params/1))
      )

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("add_step", _params, socket) do
    changeset = socket.assigns.form.source
    steps = Ecto.Changeset.get_field(changeset, :steps) || []

    new_step = %Cookbook.Recipes.Step{position: length(steps)}
    updated = steps ++ [new_step]

    changeset =
      socket.assigns.recipe
      |> Recipes.change_recipe(
        changeset.params
        |> Map.put("steps", build_nested_params(updated, &step_to_params/1))
      )

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("update_tags_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, tags_input: value)}
  end

  def handle_info({:ai_result, {:ok, attrs}}, socket) do
    attrs = Map.put(attrs, "user_id", socket.assigns.current_user.id)

    recipe = %Recipe{
      user_id: socket.assigns.current_user.id,
      ingredients: [],
      steps: [],
      tags: []
    }

    changeset = Recipes.change_recipe(recipe, attrs)

    {:noreply,
     socket
     |> assign(
       form: to_form(changeset),
       recipe: recipe,
       tags_input: Enum.join(attrs["tags"] || [], ", "),
       tab: "manual",
       ai_loading: false
     )
     |> put_flash(:info, "Recipe data loaded! Review and save.")}
  end

  def handle_info({:ai_result, {:error, reason}}, socket) do
    msg =
      case reason do
        :missing_api_key ->
          "OPENROUTER_API_KEY is not configured."

        {:http_error, status} ->
          "Failed to fetch URL (HTTP #{status})."

        {:api_error, status, %{"error" => %{"message" => message}}} ->
          "AI error (#{status}): #{message}"

        {:api_error, status, _body} ->
          "AI request failed with status #{status}."

        {:request_failed, reason} ->
          "AI request failed: #{inspect(reason)}"

        {:json_parse_error, _text} ->
          "Failed to parse AI response. Please try again."

        _ ->
          "AI request failed. Please try again."
      end

    {:noreply,
     socket
     |> assign(ai_loading: false)
     |> put_flash(:error, msg)}
  end

  defp process_tags(recipe_params, socket) do
    tags_input = recipe_params["tags_input"] || socket.assigns.tags_input || ""

    tags =
      tags_input
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    recipe_params
    |> Map.put("tags", tags)
    |> Map.put("user_id", socket.assigns.current_user.id)
  end

  defp save_recipe(socket, :new, recipe_params) do
    case Recipes.create_recipe(recipe_params) do
      {:ok, recipe} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recipe created!")
         |> push_navigate(to: ~p"/recipes/#{recipe.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_recipe(socket, :edit, recipe_params) do
    case Recipes.update_recipe(socket.assigns.recipe, recipe_params) do
      {:ok, recipe} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recipe updated!")
         |> push_navigate(to: ~p"/recipes/#{recipe.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp build_nested_params(items, to_params_fn) do
    items
    |> Enum.with_index()
    |> Enum.map(fn {item, idx} -> {to_string(idx), to_params_fn.(item)} end)
    |> Map.new()
  end

  defp ingredient_to_params(%{} = ing) do
    %{
      "name" => Map.get(ing, :name, "") || "",
      "quantity" => Map.get(ing, :quantity, "") || "",
      "unit" => Map.get(ing, :unit, "") || "",
      "group_name" => Map.get(ing, :group_name, "") || "",
      "position" => to_string(Map.get(ing, :position, 0))
    }
  end

  defp step_to_params(%{} = step) do
    %{
      "instruction" => Map.get(step, :instruction, "") || "",
      "position" => to_string(Map.get(step, :position, 0)),
      "duration_minutes" => to_string(Map.get(step, :duration_minutes, "") || "")
    }
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <.header>
        {@page_title}
      </.header>

      <%!-- Tab selector (only on new recipe) --%>
      <div :if={@action == :new} class="mt-6 grid grid-cols-3 rounded-xl border border-base-300/50 overflow-hidden">
        <button
          :for={{label, tab, icon} <- [{"Manual", "manual", "hero-pencil-square"}, {"Import URL", "url", "hero-link"}, {"Generate AI", "ai", "hero-sparkles"}]}
          type="button"
          phx-click="switch_tab"
          phx-value-tab={tab}
          class={[
            "flex items-center justify-center gap-1 sm:gap-2 py-3 text-xs sm:text-sm font-medium transition-colors",
            @tab == tab && "bg-primary text-white" || "bg-base-200 text-base-content/60 hover:bg-base-200"
          ]}
        >
          <.icon name={icon} class="size-4" />
          <span class="hidden sm:inline">{label}</span>
          <span class="sm:hidden">{if(label == "Import URL", do: "URL", else: if(label == "Generate AI", do: "AI", else: label))}</span>
        </button>
      </div>

      <%!-- Import from URL tab --%>
      <div :if={@tab == "url" && @action == :new} class="mt-6">
        <div class="rounded-xl border border-base-300/50 bg-base-200 p-6">
          <h3 class="font-semibold mb-4">Import from URL</h3>
          <form phx-submit="import_url" class="space-y-4">
            <.input type="url" name="url" value={@ai_url} label="Recipe URL" placeholder="https://example.com/recipe" required />
            <.button type="submit" variant="primary" disabled={@ai_loading} phx-disable-with="Importing...">
              <.icon name="hero-arrow-down-tray" class="size-4 mr-1" />
              {if @ai_loading, do: "Importing...", else: "Import Recipe"}
            </.button>
          </form>
        </div>
      </div>

      <%!-- Generate with AI tab --%>
      <div :if={@tab == "ai" && @action == :new} class="mt-6">
        <div class="rounded-xl border border-base-300/50 bg-base-200 p-6">
          <h3 class="font-semibold mb-4">Generate with AI</h3>
          <form phx-submit="generate_recipe" class="space-y-4">
            <.input type="textarea" name="prompt" value={@ai_prompt} label="Describe the recipe you want"
              placeholder="e.g. a quick pasta dish with mushrooms and cream" required />
            <.button type="submit" variant="primary" disabled={@ai_loading} phx-disable-with="Generating...">
              <.icon name="hero-sparkles" class="size-4 mr-1" />
              {if @ai_loading, do: "Generating...", else: "Generate Recipe"}
            </.button>
          </form>
        </div>
      </div>

      <%!-- Manual form (always shown for edit, shown for manual tab on new) --%>
      <div :if={@tab == "manual" || @action == :edit} class="mt-6">
        <.form for={@form} id="recipe-form" phx-change="validate" phx-submit="save" class="space-y-6">
          <%!-- Basic info card --%>
          <div class="rounded-xl border border-base-300/50 bg-base-200 p-6 space-y-4">
            <h3 class="font-semibold text-base">Basic Information</h3>
            <.input field={@form[:title]} type="text" label="Title" required />
            <.input field={@form[:description]} type="textarea" label="Description" />
            <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <.input field={@form[:servings]} type="number" label="Servings" />
              <.input field={@form[:prep_time_minutes]} type="number" label="Prep time (min)" />
              <.input field={@form[:cook_time_minutes]} type="number" label="Cook time (min)" />
            </div>
          </div>

          <%!-- Tags & media card --%>
          <div class="rounded-xl border border-base-300/50 bg-base-200 p-6 space-y-4">
            <h3 class="font-semibold text-base">Tags & Media</h3>
            <div>
              <label class="label mb-1">Tags (comma-separated)</label>
              <input
                type="text"
                name="recipe[tags_input]"
                value={@tags_input}
                phx-blur="update_tags_input"
                placeholder="e.g. italian, quick, vegetarian"
                class="w-full input"
              />
            </div>
            <.input field={@form[:image_url]} type="url" label="Image URL" />
            <.input field={@form[:source_url]} type="url" label="Source URL" />
            <.input field={@form[:notes]} type="textarea" label="Notes" />
          </div>

          <%!-- Ingredients card --%>
          <div class="rounded-xl border border-base-300/50 bg-base-200 p-6">
            <div class="flex items-center justify-between mb-4">
              <h3 class="font-semibold text-base">Ingredients</h3>
              <button type="button" phx-click="add_ingredient" class="text-sm font-medium text-primary hover:text-primary/80 transition-colors">
                + Add Ingredient
              </button>
            </div>
            <.inputs_for :let={ing_form} field={@form[:ingredients]}>
              <input type="hidden" name="recipe[ingredients_sort][]" value={ing_form.index} />
              <div class="flex flex-wrap sm:flex-nowrap gap-2 mb-3 items-end">
                <div class="w-[calc(50%-0.25rem)] sm:w-20">
                  <.input field={ing_form[:quantity]} type="text" placeholder="Qty" />
                </div>
                <div class="w-[calc(50%-0.25rem)] sm:w-20">
                  <.input field={ing_form[:unit]} type="text" placeholder="Unit" />
                </div>
                <div class="flex-1 min-w-0">
                  <.input field={ing_form[:name]} type="text" placeholder="Ingredient name" />
                </div>
                <input type="hidden" name="recipe[ingredients_drop][]" />
                <label class="cursor-pointer">
                  <input
                    type="checkbox"
                    name="recipe[ingredients_drop][]"
                    value={ing_form.index}
                    class="hidden"
                  />
                  <span class="flex items-center justify-center w-8 h-8 rounded-lg hover:bg-error/10 text-base-content/30 hover:text-error transition-colors">
                    <.icon name="hero-trash" class="size-4" />
                  </span>
                </label>
              </div>
            </.inputs_for>
            <input type="hidden" name="recipe[ingredients_drop][]" />
            <div :if={@form[:ingredients].value == [] || @form[:ingredients].value == nil} class="text-center py-4 text-base-content/40 text-sm">
              No ingredients yet. Click "+ Add Ingredient" to start.
            </div>
          </div>

          <%!-- Steps card --%>
          <div class="rounded-xl border border-base-300/50 bg-base-200 p-6">
            <div class="flex items-center justify-between mb-4">
              <h3 class="font-semibold text-base">Instructions</h3>
              <button type="button" phx-click="add_step" class="text-sm font-medium text-primary hover:text-primary/80 transition-colors">
                + Add Step
              </button>
            </div>
            <.inputs_for :let={step_form} field={@form[:steps]}>
              <input type="hidden" name="recipe[steps_sort][]" value={step_form.index} />
              <div class="flex gap-3 mb-4 items-start">
                <div class="flex items-center justify-center w-7 h-7 rounded-full bg-primary text-white text-xs font-bold shrink-0 mt-1">
                  {step_form.index + 1}
                </div>
                <div class="flex-1 min-w-0 space-y-2">
                  <.input field={step_form[:instruction]} type="textarea" placeholder="Describe this step..." />
                  <div class="flex items-center gap-2">
                    <div class="w-24">
                      <.input field={step_form[:duration_minutes]} type="number" placeholder="Min" />
                    </div>
                    <input type="hidden" name="recipe[steps_drop][]" />
                    <label class="cursor-pointer">
                      <input
                        type="checkbox"
                        name="recipe[steps_drop][]"
                        value={step_form.index}
                        class="hidden"
                      />
                      <span class="flex items-center justify-center w-8 h-8 rounded-lg hover:bg-error/10 text-base-content/30 hover:text-error transition-colors">
                        <.icon name="hero-trash" class="size-4" />
                      </span>
                    </label>
                  </div>
                </div>
              </div>
            </.inputs_for>
            <input type="hidden" name="recipe[steps_drop][]" />
            <div :if={@form[:steps].value == [] || @form[:steps].value == nil} class="text-center py-4 text-base-content/40 text-sm">
              No steps yet. Click "+ Add Step" to start.
            </div>
          </div>

          <div class="flex gap-3">
            <.button type="submit" variant="primary" phx-disable-with="Saving...">
              <.icon name="hero-check" class="size-4 mr-1" />
              Save Recipe
            </.button>
            <.button navigate={if @action == :edit, do: ~p"/recipes/#{@recipe.id}", else: ~p"/recipes"}>
              Cancel
            </.button>
          </div>
        </.form>
      </div>
    </div>
    """
  end
end

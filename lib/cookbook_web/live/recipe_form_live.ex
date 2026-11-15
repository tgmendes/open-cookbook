defmodule CookbookWeb.RecipeFormLive do
  use CookbookWeb, :live_view
  alias Cookbook.{Recipes, AI}
  alias Cookbook.Recipes.{Recipe, Ingredient, Step}

  @suggestions [
    "A quick weeknight pasta with pantry staples",
    "Healthy meal prep bowls for the week",
    "A comforting soup for a cold day",
    "Something impressive for a dinner party"
  ]

  def mount(params, _session, socket) do
    user_id = socket.assigns.current_user.id

    recipe =
      if params["id"],
        do: Recipes.get_recipe!(params["id"]),
        else: %Recipe{user_id: user_id, ingredients: [], steps: [], tags: []}

    if recipe.user_id != user_id do
      {:ok, push_navigate(socket, to: ~p"/recipes")}
    else
      action = if recipe.id, do: :edit, else: :new
      mode = if params["mode"] in ["url", "generate", "ai"], do: :ai, else: :manual

      {:ok,
       socket
       |> assign(
         recipe: recipe,
         action: action,
         page_title: if(action == :edit, do: "Edit recipe", else: "New recipe"),
         form: to_form(Recipes.change_recipe(recipe)),
         tags_input: Enum.join(recipe.tags || [], ", "),
         creation_mode: mode,
         input_kind: params["mode"],
         ai_loading: false,
         ai_error: nil,
         recipe_attrs: nil,
         recipe_ready?: false,
         ai_suggestions: [],
         ai_form: to_form(%{"ai_input" => ""}),
         refine_form: to_form(%{"refine_input" => ""})
       )
       |> stream(:messages, [])
       |> allow_upload(:recipe_image,
         accept: ~w(.jpg .jpeg .png .webp),
         max_entries: 1,
         max_file_size: 10_000_000
       ), layout: false}
    end
  end

  def handle_event("set_creation_mode", %{"mode" => mode}, socket),
    do: {:noreply, assign(socket, creation_mode: if(mode == "manual", do: :manual, else: :ai))}

  def handle_event("validate-upload", params, socket),
    do: {:noreply, assign(socket, ai_form: to_form(%{"ai_input" => params["ai_input"] || ""}))}

  def handle_event("cancel-upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :recipe_image, ref)}

  def handle_event("use_suggestion", %{"text" => text}, socket),
    do: {:noreply, assign(socket, ai_form: to_form(%{"ai_input" => text}))}

  def handle_event("ai_submit", params, socket) do
    text = String.trim(params["ai_input"] || "")
    system = socket.assigns.current_user.unit_system

    cond do
      socket.assigns.ai_loading ->
        {:noreply, socket}

      Enum.any?(socket.assigns.uploads.recipe_image.entries, &(!&1.done?)) ->
        {:noreply, assign(socket, ai_error: "Wait for the photo to finish uploading.")}

      socket.assigns.uploads.recipe_image.entries != [] ->
        case consume_uploaded_entries(socket, :recipe_image, fn %{path: path}, _ ->
               {:ok, Base.encode64(File.read!(path))}
             end) do
          [image] ->
            run_ai(socket, "Extract recipe from photo", fn ->
              {:recipe, AI.extract_recipe_from_image(image, system)}
            end)

          _ ->
            {:noreply, assign(socket, ai_error: "Wait for the photo to finish uploading.")}
        end

      Regex.match?(~r/https?:\/\//, text) ->
        [url | _] = Regex.run(~r/https?:\/\/[^\s]+/, text)

        run_ai(socket, "Import recipe from #{url}", fn ->
          {:recipe, AI.scrape_recipe_from_url(url, system)}
        end)

      text == "" ->
        {:noreply,
         assign(socket, ai_error: "Describe a recipe, paste a link, or upload a photo.")}

      true ->
        run_ai(socket, text, fn -> {:suggestions, AI.suggest_recipes(text)} end)
    end
  end

  def handle_event("pick_suggestion", %{"index" => value}, socket) do
    with {index, ""} <- Integer.parse(value),
         suggestion when is_map(suggestion) <- Enum.at(socket.assigns.ai_suggestions, index),
         false <- socket.assigns.ai_loading do
      system = socket.assigns.current_user.unit_system

      run_ai(socket, suggestion["title"], fn ->
        {:recipe,
         AI.generate_recipe("#{suggestion["title"]}. #{suggestion["description"]}", system)}
      end)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("ai_refine", %{"refine_input" => value}, socket) do
    text = String.trim(value)

    if text != "" && socket.assigns.recipe_attrs && !socket.assigns.ai_loading do
      attrs = socket.assigns.recipe_attrs
      system = socket.assigns.current_user.unit_system
      run_ai(socket, text, fn -> {:recipe, AI.refine_recipe(attrs, text, system)} end)
    else
      {:noreply, socket}
    end
  end

  def handle_event("validate", %{"recipe" => params}, socket) do
    params = process_tags(params, socket)

    changeset =
      Recipes.change_recipe(socket.assigns.recipe, params) |> Map.put(:action, :validate)

    {:noreply,
     assign(socket,
       form: to_form(changeset),
       tags_input: params["tags_input"] || socket.assigns.tags_input
     )}
  end

  def handle_event("save", %{"recipe" => params}, socket) do
    params = process_tags(params, socket)

    result =
      if socket.assigns.action == :new,
        do: Recipes.create_recipe(params),
        else: Recipes.update_recipe(socket.assigns.recipe, params)

    case result do
      {:ok, recipe} ->
        {:noreply,
         socket
         |> put_flash(:info, "Recipe saved.")
         |> push_navigate(to: ~p"/recipes/#{recipe.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("add_ingredient", _, socket),
    do: add_nested(socket, :ingredients, %Ingredient{})

  def handle_event("add_step", _, socket), do: add_nested(socket, :steps, %Step{})

  def handle_async(:ai, {:ok, {:suggestions, {:ok, suggestions}}}, socket) do
    {:noreply,
     socket
     |> assign(ai_loading: false, ai_suggestions: suggestions)
     |> message(:assistant, "Pick an idea below, or try another description.")}
  end

  def handle_async(:ai, {:ok, {:recipe, {:ok, attrs}}}, socket) do
    attrs = Map.put(attrs, "user_id", socket.assigns.current_user.id)

    recipe = %Recipe{
      user_id: socket.assigns.current_user.id,
      ingredients: [],
      steps: [],
      tags: []
    }

    {:noreply,
     socket
     |> assign(
       recipe: recipe,
       form: to_form(Recipes.change_recipe(recipe, attrs)),
       recipe_attrs: attrs,
       recipe_ready?: true,
       ai_loading: false,
       ai_suggestions: [],
       tags_input: Enum.join(attrs["tags"] || [], ", ")
     )
     |> message(
       :assistant,
       "Your recipe is ready to review. Edit anything, then save it to your collection."
     )}
  end

  def handle_async(:ai, _, socket),
    do:
      {:noreply,
       assign(socket,
         ai_loading: false,
         ai_error:
           "Couldn't complete that request. Please try again, or write the recipe yourself."
       )}

  defp run_ai(socket, text, function) do
    {:noreply,
     socket
     |> assign(ai_loading: true, ai_error: nil)
     |> message(:user, text)
     |> start_async(:ai, function)}
  end

  defp message(socket, role, content),
    do:
      stream_insert(socket, :messages, %{
        id: System.unique_integer([:positive]),
        role: role,
        content: content
      })

  defp process_tags(params, socket) do
    tags =
      String.split(params["tags_input"] || socket.assigns.tags_input, ",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    params |> Map.put("tags", tags) |> Map.put("user_id", socket.assigns.current_user.id)
  end

  defp add_nested(socket, field, new) do
    changeset = socket.assigns.form.source
    items = Ecto.Changeset.get_field(changeset, field) || []

    params =
      (items ++ [Map.put(new, :position, length(items))])
      |> Enum.with_index()
      |> Map.new(fn {item, index} ->
        fields =
          if field == :steps,
            do: [:id, :instruction, :short_title, :position, :duration_minutes],
            else: [:id, :name, :quantity, :unit, :group_name, :position]

        {to_string(index), Map.new(fields, &{to_string(&1), Map.get(item, &1)})}
      end)

    changeset =
      Recipes.change_recipe(
        socket.assigns.recipe,
        Map.put(changeset.params || %{}, to_string(field), params)
      )

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app {assigns}>
      <div class="mx-auto max-w-6xl space-y-6">
        <header class="flex flex-wrap items-center justify-between gap-4">
          <div>
            <.link
              navigate="/recipes"
              class="inline-flex min-h-11 items-center gap-2 text-sm text-muted"
            >
              <.icon name="hero-arrow-left" class="size-4" />Back to recipes
            </.link>
            <h1 class="mt-1 text-4xl">{@page_title}</h1>
            <p class="mt-2 text-muted">A recipe worth keeping.</p>
          </div>
          <div
            :if={@action == :new}
            class="flex rounded-xl border border-base-300 bg-base-200 p-1"
            role="tablist"
            aria-label="Recipe creation"
          >
            <button
              id="mode-manual"
              role="tab"
              aria-selected={to_string(@creation_mode == :manual)}
              phx-click="set_creation_mode"
              phx-value-mode="manual"
              class={[
                "min-h-11 rounded-lg px-4 text-sm font-bold",
                @creation_mode == :manual && "bg-base-content text-base-100"
              ]}
            >
              Write it yourself
            </button><button
              id="mode-ai"
              role="tab"
              aria-selected={to_string(@creation_mode == :ai)}
              phx-click="set_creation_mode"
              phx-value-mode="ai"
              class={[
                "min-h-11 rounded-lg px-4 text-sm font-bold",
                @creation_mode == :ai && "bg-base-content text-base-100"
              ]}
            >Use AI</button>
          </div>
        </header>
        <div class={[
          "grid items-start gap-7",
          @creation_mode == :ai && @action == :new && "xl:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]"
        ]}>
          <section
            :if={@action == :new && @creation_mode == :ai}
            class="surface space-y-5 p-5 sm:p-6 xl:order-2"
            aria-label="Recipe assistant"
          >
            <div class="flex items-center gap-3">
              <span class="flex size-11 items-center justify-center rounded-xl bg-lavender text-lavender-ink">
                <.icon name="hero-sparkles" class="size-6" />
              </span>
              <div>
                <h2 class="text-xl">A little kitchen inspiration</h2>
                <p class="text-sm text-muted">Describe it, link it, or snap a photo.</p>
              </div>
            </div>
            <div
              id="assistant-messages"
              phx-update="stream"
              phx-hook="ScrollToBottom"
              class="max-h-72 space-y-3 overflow-y-auto"
            >
              <p
                :for={{id, msg} <- @streams.messages}
                id={id}
                class={[
                  "rounded-2xl p-3.5 text-sm leading-relaxed",
                  if(msg.role == :user, do: "ml-5 bg-tag", else: "mr-5 bg-lavender text-lavender-ink")
                ]}
              >
                {msg.content}
              </p>
            </div>
            <p
              :if={@ai_loading}
              role="status"
              class="rounded-xl bg-butter p-3 text-sm text-butter-ink"
            >
              Working on something good…
            </p>
            <p
              :if={@ai_error}
              id="ai-error"
              role="alert"
              class="rounded-xl bg-blush p-3 text-sm text-blush-ink"
            >
              {@ai_error}
            </p>
            <div :if={@ai_suggestions != []} id="recipe-suggestions" class="space-y-2">
              <button
                :for={{idea, i} <- Enum.with_index(@ai_suggestions)}
                phx-click="pick_suggestion"
                phx-value-index={i}
                disabled={@ai_loading}
                class="surface min-h-11 w-full space-y-1 p-4 text-left transition-colors hover:border-strong"
              >
                <span class="block font-heading font-semibold">{idea["title"]}</span><span class="block text-sm text-muted">{idea["description"]}</span>
              </button>
            </div>
            <.form
              for={@ai_form}
              id="creator-form"
              phx-submit="ai_submit"
              phx-change="validate-upload"
              class="space-y-3"
            >
              <.input
                field={@ai_form[:ai_input]}
                type="textarea"
                aria-label="Describe a recipe or paste a link"
                placeholder={
                  if @input_kind == "url",
                    do: "Paste a recipe link…",
                    else: "What would you like to cook?"
                }
                rows="3"
                disabled={@ai_loading}
                class="field min-h-28 resize-y"
              /><label class="block text-sm font-bold" for={@uploads.recipe_image.ref}>
                Or upload a recipe photo
              </label>
              <.live_file_input upload={@uploads.recipe_image} class="field text-sm" />
              <p
                :for={error <- upload_errors(@uploads.recipe_image)}
                role="alert"
                class="text-sm text-blush-ink"
              >
                Upload error: {error}
              </p>
              <div :for={entry <- @uploads.recipe_image.entries} class="flex items-center gap-3">
                <.live_img_preview entry={entry} class="size-12 rounded-xl object-cover" /><span class="min-w-0 flex-1 truncate text-sm">
                  {entry.client_name}
                </span><button
                  phx-click="cancel-upload"
                  phx-value-ref={entry.ref}
                  type="button"
                  aria-label="Remove photo"
                  class="action size-11 !p-0"
                ><.icon name="hero-x-mark" class="size-5" /></button>
                <p
                  :for={error <- upload_errors(@uploads.recipe_image, entry)}
                  class="text-sm text-blush-ink"
                >
                  {error}
                </p>
              </div>
              <button type="submit" disabled={@ai_loading} class="action action-primary w-full">
                {if @ai_loading, do: "Working…", else: "Find my recipe"}
              </button>
            </.form>
            <div :if={!@recipe_ready?} class="flex flex-wrap gap-2">
              <button
                :for={suggestion <- suggestions()}
                phx-click="use_suggestion"
                phx-value-text={suggestion}
                class="min-h-11 rounded-xl border border-base-300 px-3 py-2 text-left text-xs text-secondary-ink hover:bg-tag"
              >
                {suggestion}
              </button>
            </div>
            <.form
              :if={@recipe_ready?}
              for={@refine_form}
              id="refine-form"
              phx-submit="ai_refine"
              class="space-y-3 border-t border-base-300 pt-4"
            >
              <.input
                field={@refine_form[:refine_input]}
                label="Want to change something?"
                placeholder="Make it spicier, or serve four…"
                disabled={@ai_loading}
                class="field"
              /><button class="action w-full" type="submit" disabled={@ai_loading}>
                Refine recipe
              </button>
            </.form>
          </section>
          <section
            :if={@action == :edit || @creation_mode == :manual || @recipe_ready?}
            class="min-w-0 xl:order-1"
          >
            <.form
              for={@form}
              id="recipe-form"
              phx-change="validate"
              phx-submit="save"
              class="space-y-5"
            >
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
                  <input type="hidden" name="recipe[ingredients_sort][]" value={ing.index} />
                  <div class="space-y-3 rounded-2xl bg-tag p-3">
                    <.input
                      field={ing[:name]}
                      label={"Ingredient #{ing.index + 1}"}
                      placeholder="Ingredient name"
                    />
                    <div class="grid grid-cols-[minmax(0,1fr)_minmax(0,1fr)_44px] items-end gap-2">
                      <.input field={ing[:quantity]} label="Quantity" /><.input
                        field={ing[:unit]}
                        type="select"
                        label="Unit"
                        options={Ingredient.unit_options(@current_user.unit_system)}
                      /><label
                        class="flex size-11 cursor-pointer items-center justify-center rounded-xl hover:bg-blush"
                        title="Remove ingredient"
                      >
                        <input
                          type="checkbox"
                          name="recipe[ingredients_drop][]"
                          value={ing.index}
                          class="peer sr-only"
                          aria-label={"Remove ingredient #{ing.index + 1}"}
                        /><span class="rounded p-1 peer-focus-visible:outline-2">
                          <.icon name="hero-trash" class="size-5" />
                        </span>
                      </label>
                    </div>
                  </div>
                </.inputs_for>
                <input type="hidden" name="recipe[ingredients_drop][]" />
              </section>
              <section class="surface space-y-4 p-5 sm:p-6">
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <h2 class="text-xl">Method</h2>
                  <button id="add-step" type="button" phx-click="add_step" class="action">
                    <.icon name="hero-plus" class="size-4" />Add step
                  </button>
                </div>
                <.inputs_for :let={step} field={@form[:steps]}>
                  <input type="hidden" name="recipe[steps_sort][]" value={step.index} />
                  <div class="space-y-3 rounded-2xl bg-tag p-4">
                    <div class="flex items-center justify-between">
                      <h3 class="text-lg">Step {step.index + 1}</h3>
                      <label
                        class="flex size-11 cursor-pointer items-center justify-center rounded-xl hover:bg-blush"
                        title="Remove step"
                      >
                        <input
                          type="checkbox"
                          name="recipe[steps_drop][]"
                          value={step.index}
                          class="peer sr-only"
                          aria-label={"Remove step #{step.index + 1}"}
                        /><span class="rounded p-1 peer-focus-visible:outline-2">
                          <.icon name="hero-trash" class="size-5" />
                        </span>
                      </label>
                    </div>
                    <.input
                      field={step[:short_title]}
                      label="Short title (optional)"
                      placeholder="e.g. Start the rice"
                    /><.input
                      field={step[:instruction]}
                      type="textarea"
                      label="Instructions"
                      rows="3"
                    /><.input
                      field={step[:duration_minutes]}
                      type="number"
                      min="0"
                      label="Timer (minutes, optional)"
                    />
                  </div>
                </.inputs_for>
                <input type="hidden" name="recipe[steps_drop][]" />
              </section>
              <section class="surface space-y-4 p-5 sm:p-6">
                <h2 class="text-xl">Make it yours</h2>
                <.input
                  name="recipe[tags_input]"
                  value={@tags_input}
                  id="recipe-tags"
                  label="Tags (separated by commas)"
                  placeholder="vegetarian, quick, comfort"
                /><.input field={@form[:image_url]} type="url" label="Image URL" /><.input
                  field={@form[:source_url]}
                  type="url"
                  label="Source URL"
                /><.input field={@form[:notes]} type="textarea" label="Kitchen notes" />
              </section>
              <div class="flex flex-wrap gap-3">
                <button type="submit" phx-disable-with="Saving…" class="action action-primary">
                  Save recipe <.icon name="hero-check" class="size-4" />
                </button><.link
                  navigate={if @action == :edit, do: ~p"/recipes/#{@recipe.id}", else: ~p"/recipes"}
                  class="action"
                >Cancel</.link>
              </div>
            </.form>
          </section>
          <section
            :if={@action == :new && @creation_mode == :ai && !@recipe_ready?}
            class="flex min-h-64 flex-col items-center justify-center gap-4 rounded-[20px] border border-dashed border-strong p-8 text-center xl:order-1"
          >
            <span class="flex size-16 items-center justify-center rounded-2xl bg-butter text-butter-ink">
              <.icon name="hero-book-open" class="size-8" />
            </span>
            <h2 class="text-xl">Your next favourite starts here</h2>
            <p class="max-w-sm text-sm leading-relaxed text-muted">
              Use the assistant to turn an idea, recipe link, or photo into something you can save and cook.
            </p>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp suggestions, do: @suggestions
end

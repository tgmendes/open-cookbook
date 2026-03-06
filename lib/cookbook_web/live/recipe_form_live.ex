defmodule CookbookWeb.RecipeFormLive do
  use CookbookWeb, :live_view

  alias Cookbook.Recipes
  alias Cookbook.Recipes.Recipe

  @suggestions [
    "A quick weeknight pasta with pantry staples",
    "Healthy meal prep bowls for the week",
    "A comforting soup for a cold day",
    "Something impressive for a dinner party"
  ]

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

    socket =
      socket
      |> assign(
        recipe: recipe,
        action: action,
        page_title: page_title,
        form: to_form(changeset),
        tags_input: Enum.join(recipe.tags || [], ", ")
      )
      |> allow_upload(:recipe_image,
        accept: ~w(.jpg .jpeg .png .webp),
        max_entries: 1,
        max_file_size: 10_000_000
      )

    socket =
      if action == :new do
        socket
        |> assign(
          page_full_width: true,
          ui_state: :creator_input,
          ai_input_text: "",
          ai_loading: false,
          ai_loading_message: "",
          ai_error: nil,
          ai_feedback: nil,
          recipe_attrs: nil,
          ai_suggestions: [],
          creation_mode: :ai,
          messages: [
            %{role: :assistant, content: "What would you like to cook? Describe a recipe, paste a URL, or upload a photo."}
          ]
        )
      else
        socket
      end

    {:ok, socket}
  end

  # ── AI events (only :new action) ──

  def handle_event("ai_validate", %{"value" => text}, socket) do
    {:noreply, assign(socket, ai_input_text: text)}
  end

  def handle_event("set_creation_mode", %{"mode" => mode}, socket) do
    {:noreply, assign(socket, creation_mode: if(mode == "manual", do: :manual, else: :ai))}
  end

  def handle_event("use_suggestion", %{"text" => text}, socket) do
    {:noreply, assign(socket, ai_input_text: text)}
  end

  def handle_event("dismiss_error", _params, socket) do
    {:noreply, assign(socket, ai_error: nil)}
  end

  def handle_event("dismiss_feedback", _params, socket) do
    {:noreply, assign(socket, ai_feedback: nil)}
  end

  def handle_event("ai_submit", params, socket) do
    # Read from form params first (handles mobile paste which doesn't trigger phx-keyup)
    input_text = String.trim(Map.get(params, "ai_input", socket.assigns.ai_input_text))
    socket = assign(socket, ai_input_text: input_text)
    uploads = socket.assigns.uploads.recipe_image.entries

    cond do
      uploads != [] ->
        [image_base64] =
          consume_uploaded_entries(socket, :recipe_image, fn %{path: path}, _entry ->
            data = File.read!(path)
            {:ok, Base.encode64(data)}
          end)

        user_msg = %{role: :user, content: "Extract recipe from uploaded image"}
        messages = socket.assigns.messages ++ [user_msg]

        socket =
          socket
          |> assign(
            ui_state: :loading,
            ai_loading: true,
            ai_loading_message: "Extracting from image...",
            ai_error: nil,
            messages: messages,
            ai_input_text: ""
          )

        self_pid = self()

        Task.start(fn ->
          result = Cookbook.AI.extract_recipe_from_image(image_base64, socket.assigns.current_user.unit_system)
          send(self_pid, {:ai_result, result, nil})
        end)

        {:noreply, socket}

      Regex.match?(~r/https?:\/\//, input_text) ->
        text = input_text

        url =
          Regex.run(~r/https?:\/\/[^\s]+/, text)
          |> List.first()

        if url do
          user_msg = %{role: :user, content: "Import recipe from: #{url}"}
          messages = socket.assigns.messages ++ [user_msg]

          socket =
            socket
            |> assign(
              ui_state: :loading,
              ai_loading: true,
              ai_loading_message: "Importing from URL...",
              ai_error: nil,
              messages: messages,
              ai_input_text: ""
            )

          self_pid = self()

          Task.start(fn ->
            result = Cookbook.AI.scrape_recipe_from_url(url, socket.assigns.current_user.unit_system)
            send(self_pid, {:ai_result, result, nil})
          end)

          {:noreply, socket}
        else
          {:noreply, assign(socket, ai_error: "Please enter a valid URL.")}
        end

      true ->
        if input_text == "" do
          {:noreply, assign(socket, ai_error: "Please describe what you'd like to cook.")}
        else
          user_msg = %{role: :user, content: input_text}
          messages = socket.assigns.messages ++ [user_msg]

          socket =
            socket
            |> assign(
              ui_state: :loading,
              ai_loading: true,
              ai_loading_message: "Finding recipe ideas...",
              ai_error: nil,
              messages: messages,
              ai_input_text: ""
            )

          self_pid = self()

          Task.start(fn ->
            result = Cookbook.AI.suggest_recipes(input_text)
            send(self_pid, {:ai_suggestions_result, result})
          end)

          {:noreply, socket}
        end
    end
  end

  def handle_event("pick_suggestion", %{"index" => index}, socket) do
    suggestion = Enum.at(socket.assigns.ai_suggestions, String.to_integer(index))

    prompt =
      "Create a recipe for: #{suggestion["title"]}. #{suggestion["description"]}"

    user_msg = %{role: :user, content: "→ #{suggestion["title"]}"}
    messages = socket.assigns.messages ++ [user_msg]

    socket =
      socket
      |> assign(
        ui_state: :loading,
        ai_loading: true,
        ai_loading_message: "Creating your recipe...",
        ai_error: nil,
        messages: messages
      )

    self_pid = self()

    Task.start(fn ->
      result = Cookbook.AI.generate_recipe(prompt, socket.assigns.current_user.unit_system)
      send(self_pid, {:ai_result, result, nil})
    end)

    {:noreply, socket}
  end

  def handle_event("back_to_input", _params, socket) do
    {:noreply, assign(socket, ui_state: :creator_input, ai_suggestions: [])}
  end

  def handle_event("ai_refine", %{"refine_input" => text}, socket) do
    text = String.trim(text)

    if text == "" do
      {:noreply, socket}
    else
      user_msg = %{role: :user, content: text}
      messages = socket.assigns.messages ++ [user_msg]

      socket = assign(socket, ai_loading: true, ai_feedback: nil, messages: messages)
      self_pid = self()
      attrs = socket.assigns.recipe_attrs

      Task.start(fn ->
        result = Cookbook.AI.refine_recipe(attrs, text, socket.assigns.current_user.unit_system)
        send(self_pid, {:ai_refine_result, result})
      end)

      {:noreply, socket}
    end
  end

  # ── Upload events ──

  def handle_event("validate-upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :recipe_image, ref)}
  end

  # ── Form events (shared :new and :edit) ──

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

  # ── AI result handlers ──

  def handle_info({:ai_suggestions_result, {:ok, suggestions}}, socket) do
    asst_msg = %{role: :assistant, content: "Here are #{length(suggestions)} recipe ideas — click one to get started:"}
    messages = socket.assigns.messages ++ [asst_msg]

    {:noreply,
     socket
     |> assign(
       ui_state: :picking_suggestion,
       ai_suggestions: suggestions,
       ai_loading: false,
       ai_loading_message: "",
       messages: messages
     )}
  end

  def handle_info({:ai_suggestions_result, {:error, reason}}, socket) do
    asst_msg = %{role: :assistant, content: "Sorry, couldn't find recipe ideas. #{format_error(reason)}"}
    messages = socket.assigns.messages ++ [asst_msg]

    {:noreply,
     socket
     |> assign(
       ui_state: :creator_input,
       ai_loading: false,
       ai_loading_message: "",
       ai_error: format_error(reason),
       messages: messages
     )}
  end

  def handle_info({:ai_result, {:ok, attrs}, _ref}, socket) do
    apply_recipe_attrs(socket, attrs, :recipe_ready)
  end

  def handle_info({:ai_result, {:error, reason}, _ref}, socket) do
    asst_msg = %{role: :assistant, content: "Something went wrong: #{format_error(reason)}"}
    messages = socket.assigns.messages ++ [asst_msg]

    {:noreply,
     socket
     |> assign(
       ui_state: :creator_input,
       ai_loading: false,
       ai_loading_message: "",
       ai_error: format_error(reason),
       messages: messages
     )}
  end

  def handle_info({:ai_refine_result, {:ok, attrs}}, socket) do
    apply_recipe_attrs(socket, attrs, :recipe_ready, "Recipe updated based on your request.")
  end

  def handle_info({:ai_refine_result, {:error, reason}}, socket) do
    asst_msg = %{role: :assistant, content: "Couldn't refine: #{format_error(reason)}"}
    messages = socket.assigns.messages ++ [asst_msg]

    {:noreply,
     socket
     |> assign(
       ai_loading: false,
       ai_feedback: "Failed to refine: #{format_error(reason)}",
       messages: messages
     )}
  end

  # ── Private helpers ──

  defp apply_recipe_attrs(socket, attrs, ui_state, feedback \\ nil) do
    attrs = Map.put(attrs, "user_id", socket.assigns.current_user.id)

    recipe = %Recipe{
      user_id: socket.assigns.current_user.id,
      ingredients: [],
      steps: [],
      tags: []
    }

    changeset = Recipes.change_recipe(recipe, attrs)

    asst_content = feedback || "Here's your recipe! Review and edit it, then save when you're happy."
    asst_msg = %{role: :assistant, content: asst_content}
    messages = socket.assigns.messages ++ [asst_msg]

    {:noreply,
     socket
     |> assign(
       ui_state: ui_state,
       form: to_form(changeset),
       recipe: recipe,
       tags_input: Enum.join(attrs["tags"] || [], ", "),
       recipe_attrs: attrs,
       ai_loading: false,
       ai_loading_message: "",
       ai_feedback: feedback,
       messages: messages
     )}
  end

  defp format_error(reason) do
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
        "Something went wrong. Please try again."
    end
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

  # ── Render ──

  def render(assigns) do
    ~H"""
    <%= if @action == :edit do %>
      <div class="max-w-2xl mx-auto">
        <.header>
          <div class="flex items-center gap-2">
            <.icon name="hero-pencil-square" class="size-5 text-primary" />
            {@page_title}
          </div>
        </.header>
        <div class="mt-6 pb-8">
          <.recipe_form form={@form} action={@action} recipe={@recipe} tags_input={@tags_input} uploads={@uploads} unit_system={@current_user.unit_system} />
        </div>
      </div>
    <% else %>

      <%!-- Mobile / tablet: single-column centered flow (hidden on lg+) --%>
      <div class="lg:hidden">
        <%= case @ui_state do %>
          <% :creator_input -> %>
            <.creator_input
              ai_input_text={@ai_input_text}
              ai_error={@ai_error}
              uploads={@uploads}
            />
          <% :loading -> %>
            <.loading_state message={@ai_loading_message} />
          <% :picking_suggestion -> %>
            <.suggestion_picker
              suggestions={@ai_suggestions}
              ai_input_text={@ai_input_text}
            />
          <% :recipe_ready -> %>
            <.recipe_ready_state
              form={@form}
              action={@action}
              recipe={@recipe}
              tags_input={@tags_input}
              uploads={@uploads}
              ai_loading={@ai_loading}
              ai_feedback={@ai_feedback}
              unit_system={@current_user.unit_system}
            />
        <% end %>
      </div>

      <%!-- Desktop: full-height two-column — form LEFT, AI RIGHT --%>
      <div class="hidden lg:flex flex-col" style="min-height: 100vh;">

        <%!-- Header bar --%>
        <div class="flex items-center gap-4 px-8 py-4 border-b border-base-300/50 bg-base-100 shrink-0">
          <div class="flex items-center gap-3 min-w-0">
            <.link navigate={~p"/recipes"} class="flex items-center gap-1 text-sm text-base-content/50 hover:text-base-content transition-colors shrink-0">
              <.icon name="hero-arrow-left" class="size-4" />
              Back
            </.link>
            <span class="text-base-content/30">|</span>
            <h1 class="text-lg font-bold text-base-content">New Recipe</h1>
          </div>

          <%!-- Mode tabs --%>
          <div class="flex items-center gap-1 flex-1 justify-center">
            <button
              phx-click="set_creation_mode"
              phx-value-mode="manual"
              class={[
                "px-4 py-2 rounded-lg text-sm font-medium transition-all",
                if(@creation_mode == :manual,
                  do: "bg-primary text-primary-content",
                  else: "text-base-content/60 hover:text-base-content hover:bg-base-200"
                )
              ]}
            >
              Manual
            </button>
            <button
              phx-click="set_creation_mode"
              phx-value-mode="ai"
              class={[
                "px-4 py-2 rounded-lg text-sm font-medium transition-all",
                if(@creation_mode == :ai,
                  do: "bg-primary text-primary-content",
                  else: "text-base-content/60 hover:text-base-content hover:bg-base-200"
                )
              ]}
            >
              AI
            </button>
          </div>

          <div class="shrink-0 min-w-[110px] flex justify-end">
            <%= if @ui_state == :recipe_ready || @creation_mode == :manual do %>
              <button
                form="recipe-form-desktop"
                type="submit"
                class="px-5 py-2 rounded-xl bg-primary text-primary-content text-sm font-semibold hover:bg-primary/90 transition-colors"
              >
                Save Recipe
              </button>
            <% end %>
          </div>
        </div>

        <%!-- Two-column body — fills remaining height --%>
        <div class="flex flex-1 min-h-0">

          <%!-- LEFT: form or placeholder (scrollable) --%>
          <div class="flex-1 min-h-0 overflow-y-auto px-8 py-6">
            <%= if @ui_state == :recipe_ready || @creation_mode == :manual do %>
              <.recipe_form
                form={@form}
                action={@action}
                recipe={@recipe}
                tags_input={@tags_input}
                uploads={@uploads}
                unit_system={@current_user.unit_system}
                form_id="recipe-form-desktop"
              />
            <% else %>
              <div class="h-full flex flex-col items-center justify-center gap-4 rounded-2xl border-2 border-dashed border-base-300/50 p-10 text-center min-h-[400px]">
                <div class="w-16 h-16 rounded-2xl bg-base-200 flex items-center justify-center">
                  <.icon name="hero-book-open" class="size-8 text-base-content/20" />
                </div>
                <div>
                  <p class="font-medium text-base-content/30">Your recipe will appear here</p>
                  <p class="text-sm text-base-content/20 mt-1">Describe a recipe in the chat to get started</p>
                </div>
              </div>
            <% end %>
          </div>

          <%!-- RIGHT: AI chat panel (fixed width, full height, flex column) --%>
          <div class="w-[30rem] shrink-0 border-l border-base-300/50 flex flex-col min-h-0">

            <%!-- AI header (always shown) --%>
            <div class="flex items-center gap-3 px-4 py-3.5 border-b border-base-300/50 shrink-0">
              <div class="flex items-center justify-center w-8 h-8 rounded-lg bg-primary/10 shrink-0">
                <.icon name="hero-sparkles" class="size-4 text-primary" />
              </div>
              <div>
                <p class="text-sm font-semibold text-base-content">AI Recipe Assistant</p>
                <p class="text-xs text-primary">Ready to help</p>
              </div>
            </div>

            <%!-- Chat messages (always shown, flex-1, scrollable) --%>
            <div
              id="desktop-chat-messages"
              class="flex-1 min-h-0 overflow-y-auto p-4 space-y-3"
              phx-hook="ScrollToBottom"
            >
              <%!-- Empty state when no messages --%>
              <div :if={@messages == [] && @creation_mode == :manual} class="h-full flex flex-col items-center justify-center gap-3 text-center py-8">
                <div class="w-12 h-12 rounded-xl bg-base-200 flex items-center justify-center">
                  <.icon name="hero-sparkles" class="size-6 text-base-content/20" />
                </div>
                <p class="text-sm text-base-content/40">Switch to <strong class="text-primary font-medium">Describe with AI</strong> or <strong class="text-primary font-medium">Import URL</strong> to use the AI assistant.</p>
              </div>

              <div :if={@messages == [] && @creation_mode == :ai} class="h-full flex flex-col items-center justify-center gap-3 text-center py-8">
                <div class="w-12 h-12 rounded-xl bg-base-200 flex items-center justify-center">
                  <.icon name="hero-sparkles" class="size-6 text-primary/40" />
                </div>
                <p class="text-sm text-base-content/40">Describe a recipe or paste a URL to get started.</p>
              </div>

              <%!-- Message history --%>
              <div
                :for={msg <- @messages}
                class={["flex gap-2", if(msg.role == :user, do: "justify-end", else: "")]}
              >
                <div
                  :if={msg.role == :assistant}
                  class="w-7 h-7 rounded-full bg-primary/10 flex items-center justify-center shrink-0 mt-0.5"
                >
                  <.icon name="hero-sparkles" class="size-3.5 text-primary" />
                </div>
                <div class={[
                  "max-w-[85%] rounded-2xl px-3.5 py-2.5 text-sm leading-relaxed",
                  if(msg.role == :user,
                    do: "bg-primary text-primary-content rounded-tr-sm",
                    else: "bg-base-200 text-base-content rounded-tl-sm"
                  )
                ]}>
                  {msg.content}
                </div>
              </div>

              <%!-- Suggestion cards --%>
              <div :if={@ui_state == :picking_suggestion} class="space-y-2 mt-2">
                <button
                  :for={{suggestion, index} <- Enum.with_index(@ai_suggestions)}
                  phx-click="pick_suggestion"
                  phx-value-index={index}
                  class="w-full text-left rounded-xl border border-base-300/50 bg-base-200/60 hover:bg-base-200 hover:border-primary/30 p-3 transition-all group"
                >
                  <div class="font-medium text-sm group-hover:text-primary transition-colors">{suggestion["title"]}</div>
                  <div class="text-xs text-base-content/50 mt-0.5 line-clamp-2">{suggestion["description"]}</div>
                </button>
              </div>

              <%!-- Loading indicator --%>
              <div :if={@ui_state == :loading} class="flex items-center gap-2 pl-9">
                <div class="bg-base-200 rounded-2xl rounded-tl-sm px-3.5 py-2.5">
                  <span class="loading loading-dots loading-xs text-primary"></span>
                </div>
              </div>
            </div>

            <%!-- Input (always shown, pinned to bottom, content adapts by state) --%>
            <div class="border-t border-base-300/50 p-3 shrink-0">
              <%= cond do %>
                <% @ui_state == :picking_suggestion -> %>
                  <button
                    phx-click="back_to_input"
                    class="w-full text-center text-sm text-base-content/40 hover:text-base-content transition-colors py-1"
                  >
                    None of these — try a different description
                  </button>

                <% @ui_state == :recipe_ready || @creation_mode == :manual && @ui_state == :recipe_ready -> %>
                  <form phx-submit="ai_refine" class="flex gap-2">
                    <div class="flex-1 relative">
                      <div :if={@ai_loading} class="absolute right-2 top-1/2 -translate-y-1/2">
                        <span class="loading loading-spinner loading-xs text-primary"></span>
                      </div>
                      <input
                        type="text"
                        name="refine_input"
                        placeholder="Ask anything about this recipe..."
                        class="w-full input input-sm pr-8"
                        disabled={@ai_loading}
                        autocomplete="off"
                      />
                    </div>
                    <button type="submit" class="btn btn-primary btn-sm" disabled={@ai_loading}>
                      <.icon name="hero-paper-airplane" class="size-4" />
                    </button>
                  </form>

                <% @ui_state == :loading -> %>
                  <div class="flex gap-2">
                    <input type="text" disabled placeholder="Generating..." class="flex-1 input input-sm opacity-40" />
                    <button disabled class="btn btn-primary btn-sm opacity-40">
                      <.icon name="hero-sparkles" class="size-4" />
                    </button>
                  </div>

                <% @creation_mode == :manual -> %>
                  <p class="text-xs text-center text-base-content/30 py-1">Switch to AI mode to use the assistant</p>

                <% true -> %>
                  <form
                    id="creator-form-desktop"
                    phx-submit="ai_submit"
                    phx-change="validate-upload"
                    class="space-y-2"
                  >
                    <div :if={@ai_error} class="flex items-center gap-1.5 text-xs text-error">
                      <.icon name="hero-exclamation-circle" class="size-3.5 shrink-0" />
                      {@ai_error}
                    </div>
                    <div :for={entry <- @uploads.recipe_image.entries} class="flex items-center gap-2 p-2 bg-base-200 rounded-lg">
                      <.live_img_preview entry={entry} class="w-10 h-10 object-cover rounded-md" />
                      <span class="text-xs flex-1 truncate text-base-content/70">{entry.client_name}</span>
                      <button type="button" phx-click="cancel-upload" phx-value-ref={entry.ref} class="text-base-content/30 hover:text-error transition-colors">
                        <.icon name="hero-x-mark" class="size-4" />
                      </button>
                    </div>
                    <div class="flex gap-2 items-end">
                      <textarea
                        name="ai_input"
                        phx-keyup="ai_validate"
                        rows="2"
                        placeholder="Describe a recipe or paste a URL..."
                        class="flex-1 textarea textarea-bordered textarea-sm resize-none text-sm"
                        autocomplete="off"
                      >{@ai_input_text}</textarea>
                      <div class="flex flex-col gap-1">
                        <label class="btn btn-ghost btn-sm btn-square cursor-pointer text-base-content/40 hover:text-base-content" title="Upload a photo">
                          <.icon name="hero-photo" class="size-4" />
                          <.live_file_input upload={@uploads.recipe_image} class="hidden" id="recipe-image-upload-desktop" />
                        </label>
                        <button type="submit" class="btn btn-primary btn-sm btn-square">
                          <.icon name="hero-sparkles" class="size-4" />
                        </button>
                      </div>
                    </div>
                  </form>
                  <div class="flex flex-wrap gap-1.5 mt-2">
                    <button
                      :for={suggestion <- suggestions()}
                      type="button"
                      phx-click="use_suggestion"
                      phx-value-text={suggestion}
                      class="px-2.5 py-1 rounded-full text-xs border border-base-300/50 bg-base-200/40 text-base-content/60 hover:bg-base-200 hover:text-base-content transition-all"
                    >
                      {suggestion}
                    </button>
                  </div>
              <% end %>
            </div>

          </div>

        </div>
      </div>
    <% end %>
    """
  end

  # ── State 1: Creator Input (mobile) ──

  defp creator_input(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center min-h-[60vh]">
      <div class="w-full max-w-xl mx-auto text-center space-y-6">
        <%!-- Hero heading --%>
        <div class="space-y-2">
          <h1 class="text-3xl sm:text-4xl font-bold tracking-tight">
            What would you like to cook?
          </h1>
          <p class="text-base-content/60 text-sm sm:text-base">
            Describe a recipe, paste a URL, or upload a photo
          </p>
        </div>

        <%!-- Input card --%>
        <form
          id="creator-form"
          phx-submit="ai_submit"
          phx-change="validate-upload"
          class="rounded-2xl border border-base-300/50 bg-base-200/60 backdrop-blur-sm shadow-sm overflow-hidden"
        >
          <%!-- Upload preview --%>
          <div
            :for={entry <- @uploads.recipe_image.entries}
            class="flex items-center gap-3 px-4 pt-4"
          >
            <.live_img_preview entry={entry} class="w-12 h-12 object-cover rounded-lg" />
            <span class="text-sm flex-1 truncate text-base-content/70">{entry.client_name}</span>
            <button
              type="button"
              phx-click="cancel-upload"
              phx-value-ref={entry.ref}
              class="text-base-content/40 hover:text-error transition-colors"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <%!-- Textarea --%>
          <div class="p-4 pb-0">
            <textarea
              name="ai_input"
              phx-keyup="ai_validate"
              rows="3"
              placeholder="Describe a recipe, paste a URL, or upload a photo..."
              class="w-full bg-transparent border-0 focus:ring-0 resize-none text-base placeholder:text-base-content/30 p-0"
              autocomplete="off"
            >{@ai_input_text}</textarea>
          </div>

          <%!-- Card footer --%>
          <div class="flex items-center justify-between px-4 py-3 border-t border-base-300/30">
            <%!-- Photo upload --%>
            <label class="btn btn-ghost btn-sm btn-circle cursor-pointer text-base-content/50 hover:text-base-content">
              <.icon name="hero-photo" class="size-5" />
              <.live_file_input upload={@uploads.recipe_image} class="hidden" id="recipe-image-upload" />
            </label>

            <button
              type="submit"
              class="btn btn-primary btn-sm gap-1.5 px-5"
            >
              <.icon name="hero-sparkles" class="size-4" />
              Generate
            </button>
          </div>
        </form>

        <%!-- Error --%>
        <div
          :if={@ai_error}
          class="alert alert-error shadow-sm"
        >
          <.icon name="hero-exclamation-triangle" class="size-5 shrink-0" />
          <span>{@ai_error}</span>
          <button type="button" phx-click="dismiss_error" class="btn btn-ghost btn-xs btn-circle">
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <%!-- Suggestion chips --%>
        <div class="flex flex-wrap justify-center gap-2">
          <button
            :for={suggestion <- suggestions()}
            type="button"
            phx-click="use_suggestion"
            phx-value-text={suggestion}
            class="px-4 py-2 rounded-full text-sm border border-base-300/50 bg-base-200/40 text-base-content/70 hover:bg-base-200 hover:text-base-content hover:border-base-300 transition-all duration-200 cursor-pointer"
          >
            {suggestion}
          </button>
        </div>
      </div>
    </div>
    """
  end

  # ── State 2: Loading (mobile) ──

  defp loading_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center min-h-[60vh]">
      <div class="w-full max-w-md mx-auto text-center">
        <div class="rounded-2xl border border-base-300/50 bg-base-200/60 backdrop-blur-sm p-10 space-y-5">
          <div class="flex justify-center">
            <div class="w-16 h-16 rounded-full bg-gradient-to-br from-primary/20 to-secondary/20 flex items-center justify-center animate-pulse">
              <.icon name="hero-sparkles" class="size-8 text-primary" />
            </div>
          </div>
          <p class="text-base-content/70 font-medium">{@message}</p>
          <span class="loading loading-dots loading-md text-primary"></span>
        </div>
      </div>
    </div>
    """
  end

  # ── State 3: Suggestion Picker (mobile) ──

  defp suggestion_picker(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center min-h-[60vh]">
      <div class="w-full max-w-xl mx-auto space-y-6">
        <div class="text-center space-y-2">
          <h1 class="text-2xl sm:text-3xl font-bold tracking-tight">
            Pick a recipe
          </h1>
          <p class="text-base-content/60 text-sm">
            Based on "<span class="italic">{@ai_input_text}</span>"
          </p>
        </div>

        <div class="space-y-3">
          <button
            :for={{suggestion, index} <- Enum.with_index(@suggestions)}
            phx-click="pick_suggestion"
            phx-value-index={index}
            class="w-full text-left rounded-xl border border-base-300/50 bg-base-200/60 hover:bg-base-200 hover:border-primary/30 p-5 transition-all duration-200 group"
          >
            <div class="flex items-start gap-4">
              <div class="flex items-center justify-center w-10 h-10 rounded-full bg-primary/10 text-primary shrink-0 mt-0.5 group-hover:bg-primary/20 transition-colors">
                <.icon name="hero-sparkles" class="size-5" />
              </div>
              <div class="flex-1 min-w-0">
                <h3 class="font-semibold text-base group-hover:text-primary transition-colors">
                  {suggestion["title"]}
                </h3>
                <p class="text-sm text-base-content/60 mt-1 leading-relaxed">
                  {suggestion["description"]}
                </p>
              </div>
              <.icon name="hero-chevron-right" class="size-5 text-base-content/20 group-hover:text-primary/60 shrink-0 mt-2.5 transition-colors" />
            </div>
          </button>
        </div>

        <div class="text-center">
          <button
            phx-click="back_to_input"
            class="text-sm text-base-content/50 hover:text-base-content transition-colors"
          >
            None of these &mdash; try a different description
          </button>
        </div>
      </div>
    </div>
    """
  end

  # ── State 4: Recipe Ready (mobile) ──

  defp recipe_ready_state(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto pb-24">
      <%!-- AI feedback card --%>
      <div
        :if={@ai_feedback}
        class="mb-4 flex items-center gap-3 rounded-xl border border-primary/20 bg-primary/5 px-4 py-3"
      >
        <.icon name="hero-sparkles" class="size-5 text-primary shrink-0" />
        <span class="flex-1 text-sm text-base-content/80">{@ai_feedback}</span>
        <button type="button" phx-click="dismiss_feedback" class="btn btn-ghost btn-xs btn-circle">
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>

      <.recipe_form form={@form} action={@action} recipe={@recipe} tags_input={@tags_input} uploads={@uploads} unit_system={@unit_system} />
    </div>

    <%!-- Sticky AI refinement bar --%>
    <div class="fixed bottom-0 inset-x-0 z-30 bg-base-200/80 backdrop-blur-lg border-t border-base-300/50">
      <div class="max-w-2xl mx-auto px-4 py-3">
        <form phx-submit="ai_refine" class="flex items-center gap-3">
          <div class="flex items-center justify-center w-9 h-9 rounded-lg bg-primary/10 shrink-0">
            <%= if @ai_loading do %>
              <span class="loading loading-spinner loading-sm text-primary"></span>
            <% else %>
              <.icon name="hero-sparkles" class="size-5 text-primary" />
            <% end %>
          </div>
          <input
            type="text"
            name="refine_input"
            placeholder="Ask AI to refine — e.g. &quot;make it spicier&quot;, &quot;reduce to 2 servings&quot;..."
            class="flex-1 input input-bordered input-sm h-10 bg-base-100/50"
            autocomplete="off"
            disabled={@ai_loading}
          />
          <button
            type="submit"
            class="btn btn-primary btn-sm h-10 px-4"
            disabled={@ai_loading}
          >
            Send
          </button>
        </form>
      </div>
    </div>
    """
  end

  # ── Recipe Form Component ──

  defp recipe_form(assigns) do
    assigns = assign_new(assigns, :form_id, fn -> "recipe-form" end)
    ~H"""
    <.form for={@form} id={@form_id} phx-change="validate" phx-submit="save" class="space-y-6">
      <%!-- Basic info card --%>
      <div class="rounded-xl border border-base-300/50 bg-base-200 p-6 space-y-4">
        <h3 class="font-semibold text-base flex items-center gap-2">
          <.icon name="hero-document-text" class="size-5 text-primary/70" />
          Basic Information
        </h3>
        <.input field={@form[:title]} type="text" label="Title" required />
        <.input field={@form[:description]} type="textarea" label="Description" />
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <.input field={@form[:servings]} type="number" label="Servings" />
          <.input field={@form[:prep_time_minutes]} type="number" label="Prep time (min)" />
          <.input field={@form[:cook_time_minutes]} type="number" label="Cook time (min)" />
        </div>
      </div>

      <%!-- Ingredients card --%>
      <div class="rounded-xl border border-base-300/50 bg-base-200 p-6">
        <div class="flex items-center justify-between mb-4">
          <h3 class="font-semibold text-base flex items-center gap-2">
            <.icon name="hero-list-bullet" class="size-5 text-primary/70" />
            Ingredients
          </h3>
          <button type="button" phx-click="add_ingredient" class="btn btn-ghost btn-xs gap-1 text-primary">
            <.icon name="hero-plus" class="size-3.5" />
            Add Ingredient
          </button>
        </div>
        <div class="space-y-2">
          <.inputs_for :let={ing_form} field={@form[:ingredients]}>
            <input type="hidden" name="recipe[ingredients_sort][]" value={ing_form.index} />
            <div class="group flex flex-wrap sm:flex-nowrap gap-2 items-end p-3 rounded-lg bg-base-100/40 hover:bg-base-100/70 transition-colors">
              <div class="w-[calc(50%-0.25rem)] sm:w-20">
                <.input field={ing_form[:quantity]} type="text" placeholder="Qty" />
              </div>
              <div class="w-[calc(50%-0.25rem)] sm:w-24">
                <.input field={ing_form[:unit]} type="select" options={Cookbook.Recipes.Ingredient.unit_options(@unit_system)} />
              </div>
              <div class="flex-1 min-w-0">
                <.input field={ing_form[:name]} type="text" placeholder="Ingredient name" />
              </div>
              <input type="hidden" name="recipe[ingredients_drop][]" />
              <label class="cursor-pointer opacity-100 sm:opacity-0 sm:group-hover:opacity-100 transition-opacity">
                <input
                  type="checkbox"
                  name="recipe[ingredients_drop][]"
                  value={ing_form.index}
                  class="hidden"
                />
                <span class="flex items-center gap-1 justify-center h-8 px-2 rounded-lg hover:bg-error/10 text-base-content/30 hover:text-error transition-colors text-xs whitespace-nowrap">
                  <.icon name="hero-trash" class="size-4" />
                  <span class="hidden sm:inline">Remove</span>
                </span>
              </label>
            </div>
          </.inputs_for>
        </div>
        <input type="hidden" name="recipe[ingredients_drop][]" />
        <div :if={@form[:ingredients].value == [] || @form[:ingredients].value == nil} class="text-center py-6 text-base-content/40 text-sm">
          No ingredients yet. Click "Add Ingredient" to start.
        </div>
      </div>

      <%!-- Steps card --%>
      <div class="rounded-xl border border-base-300/50 bg-base-200 p-6">
        <div class="flex items-center justify-between mb-4">
          <h3 class="font-semibold text-base flex items-center gap-2">
            <.icon name="hero-queue-list" class="size-5 text-primary/70" />
            Instructions
          </h3>
          <button type="button" phx-click="add_step" class="btn btn-ghost btn-xs gap-1 text-primary">
            <.icon name="hero-plus" class="size-3.5" />
            Add Step
          </button>
        </div>
        <div class="space-y-4">
          <.inputs_for :let={step_form} field={@form[:steps]}>
            <input type="hidden" name="recipe[steps_sort][]" value={step_form.index} />
            <div class="group rounded-xl border border-base-300/30 bg-base-100/30 p-4 space-y-3">
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <div class="flex items-center justify-center w-10 h-10 rounded-full bg-gradient-to-br from-primary to-primary/80 text-primary-content text-sm font-bold shrink-0">
                    {step_form.index + 1}
                  </div>
                  <span class="text-sm font-medium text-base-content/60">Step {step_form.index + 1}</span>
                </div>
                <input type="hidden" name="recipe[steps_drop][]" />
                <label class="cursor-pointer opacity-100 sm:opacity-0 sm:group-hover:opacity-100 transition-opacity">
                  <input
                    type="checkbox"
                    name="recipe[steps_drop][]"
                    value={step_form.index}
                    class="hidden"
                  />
                  <span class="flex items-center gap-1 justify-center h-8 px-2 rounded-lg hover:bg-error/10 text-base-content/30 hover:text-error transition-colors text-xs whitespace-nowrap">
                    <.icon name="hero-trash" class="size-4" />
                    <span class="hidden sm:inline">Remove</span>
                  </span>
                </label>
              </div>
              <.input
                field={step_form[:instruction]}
                type="textarea"
                placeholder="Describe this step..."
                class="w-full textarea min-h-[80px]"
              />
              <div class="flex items-center gap-2">
                <.icon name="hero-clock" class="size-4 text-base-content/40 shrink-0" />
                <div class="w-20">
                  <.input field={step_form[:duration_minutes]} type="number" placeholder="0" />
                </div>
                <span class="text-sm text-base-content/50">minutes</span>
              </div>
            </div>
          </.inputs_for>
        </div>
        <input type="hidden" name="recipe[steps_drop][]" />
        <div :if={@form[:steps].value == [] || @form[:steps].value == nil} class="text-center py-6 text-base-content/40 text-sm">
          No steps yet. Click "Add Step" to start.
        </div>
      </div>

      <%!-- Tags & media card --%>
      <div class="rounded-xl border border-base-300/50 bg-base-200 p-6 space-y-4">
        <h3 class="font-semibold text-base flex items-center gap-2">
          <.icon name="hero-tag" class="size-5 text-primary/70" />
          Tags & Media
        </h3>
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
    """
  end

  defp suggestions, do: @suggestions
end

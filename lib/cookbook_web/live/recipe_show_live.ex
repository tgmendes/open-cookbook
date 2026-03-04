defmodule CookbookWeb.RecipeShowLive do
  use CookbookWeb, :live_view

  alias Cookbook.{AI, Recipes}

  def mount(%{"id" => id}, _session, socket) do
    recipe = Recipes.get_recipe!(id)

    {:ok,
     assign(socket,
       recipe: recipe,
       page_title: recipe.title,
       adjust_open: false,
       adjust_loading: false,
       adjust_error: nil,
       adjusted_ingredients: nil,
       adjusted_servings: nil
     )}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Recipes.delete_recipe(socket.assigns.recipe)
    {:noreply, push_navigate(socket, to: ~p"/recipes")}
  end

  def handle_event("open_adjust", _params, socket) do
    {:noreply, assign(socket, adjust_open: true, adjust_error: nil)}
  end

  def handle_event("close_adjust", _params, socket) do
    {:noreply, assign(socket, adjust_open: false, adjust_error: nil)}
  end

  def handle_event("reset_adjust", _params, socket) do
    {:noreply, assign(socket, adjusted_ingredients: nil, adjusted_servings: nil)}
  end

  def handle_event("adjust_quantities", %{"servings" => servings_str}, socket) do
    case Integer.parse(String.trim(servings_str)) do
      {servings, ""} when servings > 0 ->
        socket = assign(socket, adjust_loading: true, adjust_error: nil)
        self_pid = self()
        recipe = socket.assigns.recipe
        unit_system = socket.assigns.current_user.unit_system

        Task.start(fn ->
          result = AI.adjust_quantities(recipe, servings, unit_system)
          send(self_pid, {:adjust_result, result})
        end)

        {:noreply, socket}

      _ ->
        {:noreply, assign(socket, adjust_error: "Please enter a valid number of servings.")}
    end
  end

  def handle_info({:adjust_result, {:ok, %{ingredients: ingredients, servings: servings}}}, socket) do
    {:noreply,
     assign(socket,
       adjust_loading: false,
       adjust_open: false,
       adjusted_ingredients: ingredients,
       adjusted_servings: servings
     )}
  end

  def handle_info({:adjust_result, {:error, _reason}}, socket) do
    {:noreply,
     assign(socket,
       adjust_loading: false,
       adjust_error: "Failed to adjust quantities. Please try again."
     )}
  end

  def render(assigns) do
    ~H"""
    <%!-- Mobile layout: linear scroll. Desktop: side-by-side panels --%>
    <div class="lg:flex lg:gap-8 lg:items-start">

      <%!-- Left panel: image + overlay info (sticky on desktop) --%>
      <div class="lg:sticky lg:top-8 lg:w-[42%] lg:self-start shrink-0">
        <div class="relative aspect-[4/3] lg:aspect-auto lg:h-[75vh] lg:max-h-[700px] rounded-2xl overflow-hidden bg-base-200">
          <%!-- Image --%>
          <img
            :if={@recipe.image_url}
            src={@recipe.image_url}
            alt={@recipe.title}
            class="absolute inset-0 w-full h-full object-cover"
          />
          <div :if={!@recipe.image_url} class="absolute inset-0 flex items-center justify-center bg-gradient-to-br from-primary/5 to-secondary/5">
            <.icon name="hero-book-open" class="size-16 text-primary/20" />
          </div>

          <%!-- Top actions overlay --%>
          <div class="absolute top-0 left-0 right-0 flex items-center justify-between p-4">
            <.link
              navigate={~p"/recipes"}
              class="flex items-center justify-center w-9 h-9 rounded-full bg-black/30 hover:bg-black/50 text-white backdrop-blur-sm transition-colors"
              aria-label="Back to recipes"
            >
              <.icon name="hero-arrow-left" class="size-5" />
            </.link>
            <div class="flex items-center gap-2">
              <.link
                navigate={~p"/recipes/#{@recipe.id}/edit"}
                class="flex items-center justify-center w-9 h-9 rounded-full bg-black/30 hover:bg-black/50 text-white backdrop-blur-sm transition-colors"
                aria-label="Edit recipe"
              >
                <.icon name="hero-pencil-square" class="size-4" />
              </.link>
              <button
                phx-click="delete"
                data-confirm="Are you sure you want to delete this recipe?"
                class="flex items-center justify-center w-9 h-9 rounded-full bg-black/30 hover:bg-black/50 text-white backdrop-blur-sm transition-colors"
                aria-label="Delete recipe"
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </div>
          </div>

          <%!-- Bottom info overlay (desktop only) --%>
          <div class="hidden lg:block absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/80 via-black/40 to-transparent p-6 pt-16">
            <span
              :if={@recipe.source_type != :manual}
              class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-white/20 text-white mb-2"
            >
              {@recipe.source_type}
            </span>
            <h1 class="text-2xl font-bold text-white leading-tight">{@recipe.title}</h1>
            <p :if={@recipe.description} class="text-white/70 text-sm mt-1.5 line-clamp-2 leading-relaxed">
              {@recipe.description}
            </p>
            <div class="flex items-center gap-3 mt-3 flex-wrap">
              <span :if={@recipe.total_time_minutes} class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-white/20 text-white text-xs font-medium">
                <.icon name="hero-clock" class="size-3.5" />
                {@recipe.total_time_minutes} min
              </span>
              <span :if={@recipe.servings || @adjusted_servings} class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-white/20 text-white text-xs font-medium">
                <.icon name="hero-users" class="size-3.5" />
                {@adjusted_servings || @recipe.servings} servings
              </span>
              <span :if={@recipe.tags != []} :for={tag <- Enum.take(@recipe.tags, 2)} class="inline-flex items-center px-2.5 py-1 rounded-full bg-white/20 text-white text-xs font-medium">
                {tag}
              </span>
            </div>
          </div>
        </div>

        <%!-- Mobile: title + stat chips below image --%>
        <div class="lg:hidden mt-4">
          <span
            :if={@recipe.source_type != :manual}
            class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium border border-primary/30 text-primary bg-primary/5 mb-2"
          >
            {@recipe.source_type}
          </span>
          <h1 class="text-2xl font-bold text-base-content leading-tight">{@recipe.title}</h1>
          <p :if={@recipe.description} class="text-base-content/60 text-sm mt-2 leading-relaxed">{@recipe.description}</p>
          <div class="flex flex-wrap gap-2 mt-3">
            <span :if={@recipe.total_time_minutes} class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-base-200 border border-base-300/50 text-sm text-base-content/70">
              <.icon name="hero-clock" class="size-3.5" />
              {@recipe.total_time_minutes} min
            </span>
            <span :if={@recipe.servings || @adjusted_servings} class="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-base-200 border border-base-300/50 text-sm text-base-content/70">
              <.icon name="hero-users" class="size-3.5" />
              {@adjusted_servings || @recipe.servings} servings
            </span>
          </div>
        </div>
      </div>

      <%!-- Right panel: actions + ingredients + steps --%>
      <div class="flex-1 min-w-0 mt-6 lg:mt-0">

        <%!-- Action bar --%>
        <div class="flex items-center justify-between gap-3 mb-6 lg:mb-8">
          <div class="flex items-center gap-2">
            <span :if={@adjusted_servings} class="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium bg-primary/10 text-primary">
              <.icon name="hero-sparkles" class="size-3" />
              Adjusted for {@adjusted_servings} servings
            </span>
            <button :if={@adjusted_ingredients} phx-click="reset_adjust" class="text-xs text-base-content/40 hover:text-base-content/70 transition-colors">
              Reset
            </button>
          </div>
          <div class="flex items-center gap-2 shrink-0">
            <button
              onclick="window.print()"
              class="hidden lg:flex items-center gap-1.5 px-3 py-2 rounded-xl border border-base-300/50 bg-base-100 hover:bg-base-200 text-base-content/70 text-sm font-medium transition-colors"
            >
              <.icon name="hero-printer" class="size-4" />
              Print
            </button>
            <button
              phx-click="open_adjust"
              class="flex items-center gap-1.5 px-3 py-2 rounded-xl border border-base-300/50 bg-base-100 hover:bg-base-200 text-base-content/70 text-sm font-medium transition-colors"
            >
              <.icon name="hero-sparkles" class="size-4 text-primary" />
              Adjust with AI
            </button>
            <.link
              :if={@recipe.steps != []}
              navigate={~p"/recipes/#{@recipe.id}/cook"}
              class="flex items-center gap-1.5 px-4 py-2 rounded-xl bg-primary text-primary-content text-sm font-semibold hover:bg-primary/90 transition-colors"
            >
              <.icon name="hero-play-solid" class="size-4" />
              Start Cooking
            </.link>
          </div>
        </div>

        <%!-- Content: two columns on desktop --%>
        <div class="lg:grid lg:grid-cols-[40%_60%] lg:gap-8">

          <%!-- Ingredients --%>
          <div :if={@recipe.ingredients != []}>
            <h2 class="font-bold text-lg text-base-content mb-1">Ingredients</h2>
            <p class="text-sm text-base-content/50 mb-4">
              For {@adjusted_servings || @recipe.servings || "?"} servings
            </p>
            <ul class="space-y-3">
              <li
                :for={ingredient <- @adjusted_ingredients || @recipe.ingredients}
                class="flex items-baseline gap-2 pb-3 border-b border-base-300/30 last:border-0"
              >
                <span class="shrink-0">
                  <span :if={ingredient.quantity && ingredient.quantity != ""} class="font-bold text-primary">{ingredient.quantity}</span>
                  <span :if={ingredient.unit && ingredient.unit != ""} class="text-base-content/50 ml-0.5">{ingredient.unit}</span>
                </span>
                <span class="text-base-content/80">{ingredient.name}</span>
              </li>
            </ul>

            <%!-- Source link --%>
            <a
              :if={@recipe.source_url}
              href={@recipe.source_url}
              target="_blank"
              class="inline-flex items-center gap-1.5 text-sm text-primary hover:text-primary/80 transition-colors mt-4"
            >
              <.icon name="hero-arrow-top-right-on-square" class="size-4" />
              View original source
            </a>
          </div>

          <%!-- Steps --%>
          <div :if={@recipe.steps != []}>
            <h2 class="font-bold text-lg text-base-content mb-4 mt-8 lg:mt-0">Steps</h2>
            <ol class="space-y-4">
              <li :for={{step, idx} <- Enum.with_index(@recipe.steps, 1)} class="flex gap-4">
                <div class="flex items-center justify-center w-8 h-8 rounded-full bg-primary text-primary-content text-sm font-bold shrink-0 mt-0.5">
                  {idx}
                </div>
                <div class="flex-1 min-w-0 pt-0.5">
                  <p class="text-base-content/80 leading-relaxed break-words">{step.instruction}</p>
                  <p :if={step.duration_minutes} class="inline-flex items-center gap-1 text-xs text-base-content/40 mt-2">
                    <.icon name="hero-clock" class="size-3.5" />
                    ~{step.duration_minutes} min
                  </p>
                </div>
              </li>
            </ol>
          </div>
        </div>

        <%!-- Notes --%>
        <div :if={@recipe.notes} class="mt-8 rounded-xl border border-base-300/50 bg-base-200 p-5">
          <h3 class="font-semibold text-sm text-base-content/60 uppercase tracking-wide mb-2">Notes</h3>
          <p class="text-base-content/70 leading-relaxed">{@recipe.notes}</p>
        </div>

        <%!-- Tags --%>
        <div :if={@recipe.tags != []} class="mt-6 flex flex-wrap gap-2">
          <span
            :for={tag <- @recipe.tags}
            class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium border border-primary/30 text-primary bg-primary/5"
          >
            {tag}
          </span>
        </div>
      </div>
    </div>

    <%!-- Mobile sticky bottom bar --%>
    <div class="lg:hidden fixed bottom-0 inset-x-0 z-20 bg-base-100/90 backdrop-blur-md border-t border-base-300/50 px-4 py-3 flex gap-3">
      <button
        phx-click="open_adjust"
        class="flex-1 flex items-center justify-center gap-2 py-3 rounded-xl border border-base-300/50 text-base-content/70 text-sm font-medium hover:bg-base-200 transition-colors"
      >
        <.icon name="hero-sparkles" class="size-4 text-primary" />
        Adjust with AI
      </button>
      <.link
        :if={@recipe.steps != []}
        navigate={~p"/recipes/#{@recipe.id}/cook"}
        class="flex-1 flex items-center justify-center gap-2 py-3 rounded-xl bg-primary text-primary-content text-sm font-semibold hover:bg-primary/90 transition-colors"
      >
        <.icon name="hero-play-solid" class="size-4" />
        Start Cooking
      </.link>
    </div>

    <%!-- Bottom padding for mobile sticky bar --%>
    <div class="lg:hidden h-20"></div>

    <%!-- Adjust quantities modal --%>
    <div :if={@adjust_open} class="fixed inset-0 z-50 flex items-center justify-center px-4">
      <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" phx-click="close_adjust" />
      <div class="relative w-full max-w-sm bg-base-100 rounded-2xl shadow-2xl p-6 space-y-5 z-10">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <div class="flex items-center justify-center w-8 h-8 rounded-lg bg-primary/10">
              <.icon name="hero-sparkles" class="size-4 text-primary" />
            </div>
            <h2 class="text-lg font-semibold">Adjust quantities</h2>
          </div>
          <button phx-click="close_adjust" class="btn btn-ghost btn-sm btn-circle" aria-label="Close">
            <.icon name="hero-x-mark" class="size-5" />
          </button>
        </div>

        <p class="text-sm text-base-content/60">
          This recipe makes <span class="font-medium text-base-content">{@recipe.servings || "?"} servings</span>.
          Enter your desired serving count and AI will scale the ingredients.
        </p>

        <form phx-submit="adjust_quantities" class="space-y-4">
          <div>
            <label class="label mb-1 text-sm font-medium">Target servings</label>
            <input
              type="number"
              name="servings"
              min="1"
              value={@recipe.servings}
              placeholder="e.g. 2"
              class="input input-bordered w-full"
              disabled={@adjust_loading}
              autofocus
            />
          </div>

          <div :if={@adjust_error} class="alert alert-error py-2 text-sm">
            <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
            {@adjust_error}
          </div>

          <button type="submit" class="btn btn-primary w-full" disabled={@adjust_loading}>
            <%= if @adjust_loading do %>
              <span class="loading loading-spinner loading-sm"></span>
              Adjusting quantities...
            <% else %>
              <.icon name="hero-sparkles" class="size-4 mr-1" />
              Adjust with AI
            <% end %>
          </button>
        </form>
      </div>
    </div>
    """
  end
end

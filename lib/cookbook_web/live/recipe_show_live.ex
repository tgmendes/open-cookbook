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
    <div>
      <.header>
        {@recipe.title}
        <:subtitle>
          <span :if={@recipe.source_type != :manual} class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium border border-primary/30 text-primary bg-primary/5">
            {@recipe.source_type}
          </span>
        </:subtitle>
        <:actions>
          <div class="flex gap-2">
            <.button :if={@recipe.steps != []} navigate={~p"/recipes/#{@recipe.id}/cook"} variant="primary">
              <.icon name="hero-play-solid" class="size-4 mr-1" /> Cook
            </.button>
            <.button navigate={~p"/recipes/#{@recipe.id}/edit"}>
              <.icon name="hero-pencil-square" class="size-4 mr-1" /> Edit
            </.button>
            <.button phx-click="delete" data-confirm="Are you sure you want to delete this recipe?">
              <.icon name="hero-trash" class="size-4 mr-1" /> Delete
            </.button>
          </div>
        </:actions>
      </.header>

      <div class="mt-6 grid grid-cols-1 md:grid-cols-3 gap-6">
        <div class="md:col-span-2 space-y-6">
          <%!-- Description card --%>
          <div :if={@recipe.description} class="rounded-xl border border-base-300/50 bg-base-200 p-6">
            <h3 class="font-semibold text-base mb-3">Description</h3>
            <p class="text-base-content/70 leading-relaxed">{@recipe.description}</p>
          </div>

          <%!-- Ingredients card --%>
          <div :if={@recipe.ingredients != []} class="rounded-xl border border-base-300/50 bg-base-200 p-6">
            <div class="flex items-center justify-between mb-4">
              <div class="flex items-center gap-3">
                <h3 class="font-semibold text-base">Ingredients</h3>
                <span :if={@adjusted_servings} class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-primary/10 text-primary">
                  <.icon name="hero-sparkles" class="size-3" />
                  Adjusted for {@adjusted_servings} servings
                </span>
              </div>
              <div class="flex items-center gap-2">
                <button :if={@adjusted_ingredients} phx-click="reset_adjust" class="btn btn-ghost btn-xs text-base-content/50">
                  Reset
                </button>
                <button phx-click="open_adjust" class="btn btn-ghost btn-xs gap-1 text-primary">
                  <.icon name="hero-sparkles" class="size-3.5" />
                  Adjust
                </button>
              </div>
            </div>
            <ul class="space-y-2">
              <li :for={ingredient <- @adjusted_ingredients || @recipe.ingredients} class="flex items-start gap-3">
                <span class="w-2 h-2 rounded-full bg-primary mt-2 shrink-0"></span>
                <span class="text-base-content/80">
                  <span :if={ingredient.quantity && ingredient.quantity != ""} class="font-medium">{ingredient.quantity}</span>
                  <span :if={ingredient.unit && ingredient.unit != ""} class="text-base-content/60">{ingredient.unit}</span>
                  {ingredient.name}
                </span>
              </li>
            </ul>
          </div>

          <%!-- Instructions card --%>
          <div :if={@recipe.steps != []} class="rounded-xl border border-base-300/50 bg-base-200 p-6">
            <h3 class="font-semibold text-base mb-4">Instructions</h3>
            <ol class="space-y-4">
              <li :for={{step, idx} <- Enum.with_index(@recipe.steps, 1)} class="flex gap-4">
                <div class="flex items-center justify-center w-8 h-8 rounded-full bg-primary text-white text-sm font-bold shrink-0">
                  {idx}
                </div>
                <div class="flex-1 min-w-0 pt-1">
                  <p class="text-base-content/80 leading-relaxed break-words">{step.instruction}</p>
                  <p :if={step.duration_minutes} class="inline-flex items-center gap-1 text-sm text-base-content/50 mt-2">
                    <.icon name="hero-clock" class="size-3.5" />
                    ~{step.duration_minutes} min
                  </p>
                </div>
              </li>
            </ol>
          </div>

          <%!-- Notes card --%>
          <div :if={@recipe.notes} class="rounded-xl border border-base-300/50 bg-base-200 p-6">
            <h3 class="font-semibold text-base mb-3">Notes</h3>
            <p class="text-base-content/70 leading-relaxed">{@recipe.notes}</p>
          </div>
        </div>

        <%!-- Sidebar --%>
        <div class="space-y-6">
          <%!-- Image --%>
          <img :if={@recipe.image_url} src={@recipe.image_url} alt={@recipe.title} class="rounded-xl w-full" />

          <%!-- Metadata card --%>
          <div class="rounded-xl border border-base-300/50 bg-base-200 p-6 space-y-4">
            <h3 class="font-semibold text-base mb-1">Details</h3>
            <div :if={@recipe.servings || @adjusted_servings} class="flex items-center gap-3">
              <div class="flex items-center justify-center w-8 h-8 rounded-lg bg-primary/10">
                <.icon name="hero-users" class="size-4 text-primary" />
              </div>
              <div>
                <div class="text-xs text-base-content/50">Servings</div>
                <div class="font-medium">{@adjusted_servings || @recipe.servings}</div>
              </div>
            </div>
            <div :if={@recipe.prep_time_minutes} class="flex items-center gap-3">
              <div class="flex items-center justify-center w-8 h-8 rounded-lg bg-primary/10">
                <.icon name="hero-clock" class="size-4 text-primary" />
              </div>
              <div>
                <div class="text-xs text-base-content/50">Prep Time</div>
                <div class="font-medium">{@recipe.prep_time_minutes} min</div>
              </div>
            </div>
            <div :if={@recipe.cook_time_minutes} class="flex items-center gap-3">
              <div class="flex items-center justify-center w-8 h-8 rounded-lg bg-primary/10">
                <.icon name="hero-fire" class="size-4 text-primary" />
              </div>
              <div>
                <div class="text-xs text-base-content/50">Cook Time</div>
                <div class="font-medium">{@recipe.cook_time_minutes} min</div>
              </div>
            </div>
            <div :if={@recipe.total_time_minutes} class="flex items-center gap-3">
              <div class="flex items-center justify-center w-8 h-8 rounded-lg bg-primary/10">
                <.icon name="hero-clock" class="size-4 text-primary" />
              </div>
              <div>
                <div class="text-xs text-base-content/50">Total Time</div>
                <div class="font-medium">{@recipe.total_time_minutes} min</div>
              </div>
            </div>
          </div>

          <%!-- Tags card --%>
          <div :if={@recipe.tags != []} class="rounded-xl border border-base-300/50 bg-base-200 p-6">
            <h3 class="font-semibold text-base mb-3">Tags</h3>
            <div class="flex flex-wrap gap-2">
              <span
                :for={tag <- @recipe.tags}
                class="inline-flex items-center px-3 py-1 rounded-full text-sm font-medium border border-primary/30 text-primary bg-primary/5"
              >
                {tag}
              </span>
            </div>
          </div>

          <%!-- Source link --%>
          <a
            :if={@recipe.source_url}
            href={@recipe.source_url}
            target="_blank"
            class="flex items-center gap-2 text-sm text-primary hover:text-primary/80 transition-colors"
          >
            <.icon name="hero-arrow-top-right-on-square" class="size-4" />
            View original source
          </a>
        </div>
      </div>

      <div class="mt-8">
        <.link navigate={~p"/recipes"} class="inline-flex items-center gap-1 text-sm text-base-content/50 hover:text-base-content transition-colors">
          <.icon name="hero-arrow-left" class="size-4" />
          Back to recipes
        </.link>
      </div>
    </div>

    <%!-- Adjust quantities modal --%>
    <div :if={@adjust_open} class="fixed inset-0 z-50 flex items-center justify-center px-4">
      <%!-- Backdrop --%>
      <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" phx-click="close_adjust" />

      <%!-- Modal panel --%>
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

defmodule CookbookWeb.RecipeShowLive do
  use CookbookWeb, :live_view

  alias Cookbook.Recipes

  def mount(%{"id" => id}, _session, socket) do
    recipe = Recipes.get_recipe!(id)
    {:ok, assign(socket, recipe: recipe, page_title: recipe.title)}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Recipes.delete_recipe(socket.assigns.recipe)
    {:noreply, push_navigate(socket, to: ~p"/recipes")}
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
            <h3 class="font-semibold text-base mb-4">Ingredients</h3>
            <ul class="space-y-2">
              <li :for={ingredient <- @recipe.ingredients} class="flex items-start gap-3">
                <span class="w-2 h-2 rounded-full bg-primary mt-2 shrink-0"></span>
                <span class="text-base-content/80">
                  <span :if={ingredient.quantity} class="font-medium">{ingredient.quantity}</span>
                  <span :if={ingredient.unit} class="text-base-content/60">{ingredient.unit}</span>
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
            <div :if={@recipe.servings} class="flex items-center gap-3">
              <div class="flex items-center justify-center w-8 h-8 rounded-lg bg-primary/10">
                <.icon name="hero-users" class="size-4 text-primary" />
              </div>
              <div>
                <div class="text-xs text-base-content/50">Servings</div>
                <div class="font-medium">{@recipe.servings}</div>
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
    """
  end
end

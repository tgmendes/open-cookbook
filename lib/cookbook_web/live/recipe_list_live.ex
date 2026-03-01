defmodule CookbookWeb.RecipeListLive do
  use CookbookWeb, :live_view

  alias Cookbook.Recipes

  def mount(_params, _session, socket) do
    recipes = Recipes.list_recipes(socket.assigns.current_user.id)
    tags = Recipes.list_tags(socket.assigns.current_user.id)

    {:ok,
     assign(socket,
       recipes: recipes,
       tags: tags,
       search: "",
       selected_tag: nil,
       page_title: "Recipes"
     )}
  end

  def handle_params(params, _uri, socket) do
    search = params["search"] || ""
    tag = params["tag"]

    recipes =
      Recipes.list_recipes(socket.assigns.current_user.id, search: search, tag: tag)

    {:noreply, assign(socket, recipes: recipes, search: search, selected_tag: tag)}
  end

  def handle_event("search", %{"search" => search}, socket) do
    params = %{"search" => search}
    params = if socket.assigns.selected_tag, do: Map.put(params, "tag", socket.assigns.selected_tag), else: params
    {:noreply, push_patch(socket, to: ~p"/recipes?#{params}")}
  end

  def handle_event("filter_tag", %{"tag" => tag}, socket) do
    tag = if tag == "", do: nil, else: tag
    params = %{}
    params = if socket.assigns.search != "", do: Map.put(params, "search", socket.assigns.search), else: params
    params = if tag, do: Map.put(params, "tag", tag), else: params
    {:noreply, push_patch(socket, to: ~p"/recipes?#{params}")}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    recipe = Recipes.get_recipe!(id)
    {:ok, _} = Recipes.delete_recipe(recipe)

    recipes = Recipes.list_recipes(socket.assigns.current_user.id,
      search: socket.assigns.search,
      tag: socket.assigns.selected_tag
    )

    {:noreply, assign(socket, recipes: recipes)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <.header>
        Recipes
        <:actions>
          <.button navigate={~p"/recipes/new"} variant="primary">
            <.icon name="hero-plus" class="size-4 mr-1" /> New Recipe
          </.button>
        </:actions>
      </.header>

      <div class="mt-6 flex flex-col sm:flex-row gap-3">
        <form phx-change="search" phx-submit="search" class="flex-1 relative">
          <span class="absolute left-3 top-1/2 -translate-y-1/2 text-base-content/40 pointer-events-none">
            <.icon name="hero-magnifying-glass" class="size-4" />
          </span>
          <input
            type="search"
            name="search"
            value={@search}
            placeholder="Search recipes..."
            class="w-full input pl-10"
            phx-debounce="300"
          />
        </form>
        <form phx-change="filter_tag">
          <.input type="select" name="tag" value={@selected_tag || ""} prompt="All Tags" options={@tags} />
        </form>
      </div>

      <div :if={@recipes == []} class="mt-16 text-center">
        <div class="flex items-center justify-center w-16 h-16 rounded-full bg-primary/10 mx-auto mb-4">
          <.icon name="hero-book-open" class="size-8 text-primary" />
        </div>
        <p class="text-base-content/60 text-lg">No recipes yet</p>
        <p class="text-base-content/40 text-sm mt-1">Get started by adding your first recipe</p>
        <.button navigate={~p"/recipes/new"} variant="primary" class="btn btn-primary mt-4">Add your first recipe</.button>
      </div>

      <div class="mt-6 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
        <.link
          :for={recipe <- @recipes}
          navigate={~p"/recipes/#{recipe.id}"}
          class="rounded-xl border border-base-300/50 bg-base-200 overflow-hidden hover:border-primary/30 transition-all duration-300 group"
        >
          <div :if={recipe.image_url} class="aspect-video overflow-hidden bg-base-200">
            <img src={recipe.image_url} alt={recipe.title} class="h-full w-full object-cover group-hover:scale-105 transition-transform duration-300" />
          </div>
          <div :if={!recipe.image_url} class="aspect-video bg-gradient-to-br from-primary/5 to-secondary/5 flex items-center justify-center">
            <.icon name="hero-book-open" class="size-10 text-primary/20" />
          </div>
          <div class="p-4">
            <h2 class="font-semibold text-base group-hover:text-primary transition-colors">
              {recipe.title}
            </h2>
            <div class="flex items-center gap-3 mt-2">
              <span :if={recipe.total_time_minutes} class="inline-flex items-center gap-1 text-sm text-base-content/50">
                <.icon name="hero-clock" class="size-3.5" />
                {recipe.total_time_minutes} min
              </span>
            </div>
            <div :if={recipe.tags != []} class="flex flex-wrap gap-1.5 mt-3">
              <span
                :for={tag <- recipe.tags}
                class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium border border-primary/30 text-primary bg-primary/5"
              >
                {tag}
              </span>
            </div>
          </div>
        </.link>
      </div>
    </div>
    """
  end
end

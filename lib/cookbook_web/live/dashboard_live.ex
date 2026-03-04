defmodule CookbookWeb.DashboardLive do
  use CookbookWeb, :live_view

  alias Cookbook.Recipes
  alias Cookbook.Planner

  defp day_name(n), do: Enum.at(~w(Mon Tue Wed Thu Fri Sat Sun), n - 1)

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    all_recipes = Recipes.list_recipes(user.id)
    recent_recipes = Enum.take(all_recipes, 4)
    recipe_count = length(all_recipes)

    week_start = Planner.normalize_to_monday(Date.utc_today())
    {:ok, plan} = Planner.get_or_create_plan_for_week(user.id, week_start)

    filled_slots = length(plan.entries)
    week_map = Enum.group_by(plan.entries, & &1.day_of_week)

    {:ok,
     assign(socket,
       page_title: "Dashboard",
       recipe_count: recipe_count,
       recent_recipes: recent_recipes,
       week_start: week_start,
       filled_slots: filled_slots,
       total_slots: 14,
       plan: plan,
       week_map: week_map
     )}
  end

  defp greeting do
    hour = DateTime.utc_now().hour

    cond do
      hour < 12 -> "Good morning"
      hour < 17 -> "Good afternoon"
      true -> "Good evening"
    end
  end

  def render(assigns) do
    ~H"""
    <div class="lg:flex lg:gap-8 lg:items-start">

      <%!-- Main content --%>
      <div class="flex-1 min-w-0">

        <%!-- Greeting --%>
        <div class="mb-8">
          <h1 class="text-3xl font-bold text-base-content">{greeting()}, Chef</h1>
          <p class="text-base-content/50 mt-1">
            {if @filled_slots > 0,
              do: "#{@filled_slots} meal#{if @filled_slots != 1, do: "s", else: ""} planned this week",
              else: "No meals planned yet this week"}
          </p>
        </div>

        <%!-- Recent Recipes --%>
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-base font-semibold text-base-content">Recent Recipes</h2>
          <.link navigate={~p"/recipes"} class="text-sm text-primary hover:text-primary/80 font-medium transition-colors">
            View all
          </.link>
        </div>

        <div :if={@recent_recipes == []} class="rounded-2xl border border-dashed border-base-300/70 bg-base-200/30 p-10 text-center mb-8">
          <.icon name="hero-book-open" class="size-10 text-primary/30 mx-auto mb-3" />
          <p class="text-base-content/50 text-sm">No recipes yet.</p>
          <.link navigate={~p"/recipes/new"} class="inline-flex items-center gap-1.5 mt-3 text-sm text-primary font-medium hover:text-primary/80 transition-colors">
            <.icon name="hero-plus" class="size-4" />
            Add your first recipe
          </.link>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4 mb-8">
          <.link
            :for={recipe <- @recent_recipes}
            navigate={~p"/recipes/#{recipe.id}"}
            class="group rounded-2xl border border-base-300/50 bg-base-100 overflow-hidden hover:border-primary/30 hover:shadow-md transition-all duration-300"
          >
            <div class="aspect-video overflow-hidden bg-base-200">
              <img
                :if={recipe.image_url}
                src={recipe.image_url}
                alt={recipe.title}
                class="h-full w-full object-cover group-hover:scale-105 transition-transform duration-500"
              />
              <div :if={!recipe.image_url} class="h-full w-full bg-gradient-to-br from-primary/5 to-secondary/5 flex items-center justify-center">
                <.icon name="hero-book-open" class="size-8 text-primary/20" />
              </div>
            </div>
            <div class="p-4">
              <h3 class="font-semibold text-sm text-base-content group-hover:text-primary transition-colors leading-snug">
                {recipe.title}
              </h3>
              <div class="flex items-center gap-3 mt-1.5">
                <span :if={recipe.total_time_minutes} class="inline-flex items-center gap-1 text-xs text-base-content/50">
                  <.icon name="hero-clock" class="size-3" />
                  {recipe.total_time_minutes} min
                </span>
                <span :if={recipe.servings} class="inline-flex items-center gap-1 text-xs text-base-content/50">
                  <.icon name="hero-users" class="size-3" />
                  {recipe.servings}
                </span>
              </div>
            </div>
          </.link>
        </div>

        <%!-- Quick actions --%>
        <h2 class="text-base font-semibold text-base-content mb-3">Quick Actions</h2>
        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <.link
            navigate={~p"/recipes/new"}
            class="group flex items-center gap-3 p-4 rounded-xl bg-base-200 border border-base-300/50 hover:border-primary/30 hover:bg-base-200/80 transition-all duration-200"
          >
            <div class="flex items-center justify-center w-9 h-9 rounded-lg bg-primary/10 group-hover:bg-primary/20 transition-colors shrink-0">
              <.icon name="hero-plus-circle-solid" class="size-5 text-primary" />
            </div>
            <div>
              <p class="font-semibold text-sm text-base-content group-hover:text-primary transition-colors">Add recipe</p>
              <p class="text-xs text-base-content/50 mt-0.5">Manual, URL, or AI</p>
            </div>
          </.link>

          <.link
            navigate={~p"/planner?week=#{Date.to_iso8601(@week_start)}"}
            class="group flex items-center gap-3 p-4 rounded-xl bg-base-200 border border-base-300/50 hover:border-secondary/30 hover:bg-base-200/80 transition-all duration-200"
          >
            <div class="flex items-center justify-center w-9 h-9 rounded-lg bg-secondary/10 group-hover:bg-secondary/20 transition-colors shrink-0">
              <.icon name="hero-calendar-days-solid" class="size-5 text-secondary" />
            </div>
            <div>
              <p class="font-semibold text-sm text-base-content group-hover:text-secondary transition-colors">Plan this week</p>
              <p class="text-xs text-base-content/50 mt-0.5">Assign meals to days</p>
            </div>
          </.link>

          <.link
            navigate={~p"/planner/shopping?week=#{Date.to_iso8601(@week_start)}"}
            class="group flex items-center gap-3 p-4 rounded-xl bg-base-200 border border-base-300/50 hover:border-accent/30 hover:bg-base-200/80 transition-all duration-200"
          >
            <div class="flex items-center justify-center w-9 h-9 rounded-lg bg-accent/10 group-hover:bg-accent/20 transition-colors shrink-0">
              <.icon name="hero-shopping-cart-solid" class="size-5 text-accent" />
            </div>
            <div>
              <p class="font-semibold text-sm text-base-content group-hover:text-accent transition-colors">Shopping list</p>
              <p class="text-xs text-base-content/50 mt-0.5">Ingredients for the week</p>
            </div>
          </.link>
        </div>
      </div>

      <%!-- Right panel: This Week (desktop only) --%>
      <div class="hidden lg:block lg:w-64 shrink-0 mt-0">

        <%!-- This Week card --%>
        <div class="rounded-2xl border border-base-300/50 bg-base-100 p-5 mb-4">
          <div class="flex items-center justify-between mb-4">
            <h2 class="font-semibold text-base-content">This Week</h2>
            <.link navigate={~p"/planner?week=#{Date.to_iso8601(@week_start)}"} class="text-base-content/40 hover:text-base-content transition-colors">
              <.icon name="hero-calendar-days" class="size-4" />
            </.link>
          </div>

          <div class="space-y-2">
            <div :for={day_num <- 1..7} class="flex items-center justify-between py-1">
              <span class="text-sm text-base-content/60 w-8">{day_name(day_num)}</span>
              <div class="flex-1 flex justify-end">
                <%= if Map.has_key?(@week_map, day_num) do %>
                  <span class="inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-primary/10 text-primary">
                    {length(Map.get(@week_map, day_num))} meal{if length(Map.get(@week_map, day_num)) != 1, do: "s", else: ""}
                  </span>
                <% else %>
                  <span class="text-xs text-base-content/30">Empty</span>
                <% end %>
              </div>
            </div>
          </div>

          <div class="mt-4 pt-4 border-t border-base-300/50">
            <div class="flex items-center justify-between text-sm">
              <span class="text-base-content/50">Planned</span>
              <span class="font-semibold text-base-content">{@filled_slots} / {@total_slots}</span>
            </div>
            <div class="mt-2 h-1.5 rounded-full bg-base-300/50 overflow-hidden">
              <div
                class="h-full rounded-full bg-gradient-to-r from-primary to-secondary transition-all duration-500"
                style={"width: #{@filled_slots / @total_slots * 100}%"}
              ></div>
            </div>
          </div>
        </div>

        <%!-- Stats card --%>
        <div class="rounded-2xl border border-base-300/50 bg-base-100 p-5">
          <h2 class="font-semibold text-base-content mb-4">Your Cookbook</h2>
          <div class="flex items-center gap-3">
            <div class="flex items-center justify-center w-10 h-10 rounded-xl bg-primary/10">
              <.icon name="hero-book-open-solid" class="size-5 text-primary" />
            </div>
            <div>
              <div class="text-2xl font-black text-base-content">{@recipe_count}</div>
              <div class="text-xs text-base-content/50">Recipe{if @recipe_count != 1, do: "s", else: ""}</div>
            </div>
          </div>
        </div>
      </div>

    </div>
    """
  end
end

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
       page_full_width: true,
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
    <%!-- Full-width 3-column layout: main content + fixed right panel --%>
    <div class="flex min-h-screen">

      <%!-- Main content area (leaves room for fixed right panel on desktop) --%>
      <div class="flex-1 min-w-0 px-6 py-8 lg:px-10 lg:pr-[22rem]">

        <%!-- Date + Greeting header --%>
        <div class="flex items-start justify-between mb-6">
          <div>
            <p class="text-xs font-semibold tracking-widest uppercase text-base-content/40 mb-1">
              {Calendar.strftime(Date.utc_today(), "%A, %B %-d")}
            </p>
            <h1 class="text-4xl font-bold text-base-content">{greeting()}, Chef</h1>
          </div>
          <.link
            navigate={~p"/recipes/new"}
            class="hidden lg:inline-flex items-center gap-2 px-5 py-2.5 rounded-xl bg-primary text-primary-content text-sm font-semibold hover:bg-primary/90 transition-colors shrink-0"
          >
            <.icon name="hero-plus" class="size-4" />
            Add Recipe
          </.link>
        </div>

        <%!-- Quick action pills --%>
        <div class="flex flex-wrap gap-2 mb-8">
          <.link
            navigate={~p"/recipes/new?mode=url"}
            class="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-full border border-base-300 bg-base-100 text-sm font-medium text-base-content/70 hover:border-primary/30 hover:text-primary transition-all"
          >
            <.icon name="hero-link" class="size-3.5" />
            Import URL
          </.link>
          <.link
            navigate={~p"/recipes/new?mode=ai"}
            class="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-full border border-primary/30 bg-primary/5 text-sm font-medium text-primary hover:bg-primary/10 transition-all"
          >
            <.icon name="hero-sparkles" class="size-3.5" />
            Describe with AI
          </.link>
          <.link
            navigate={~p"/planner?week=#{Date.to_iso8601(@week_start)}"}
            class="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-full border border-base-300 bg-base-100 text-sm font-medium text-base-content/70 hover:border-primary/30 hover:text-primary transition-all"
          >
            <.icon name="hero-calendar-days" class="size-3.5" />
            Plan this week
          </.link>
          <.link
            navigate={~p"/planner/shopping?week=#{Date.to_iso8601(@week_start)}"}
            class="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-full border border-base-300 bg-base-100 text-sm font-medium text-base-content/70 hover:border-primary/30 hover:text-primary transition-all"
          >
            <.icon name="hero-shopping-cart" class="size-3.5" />
            Shopping list
          </.link>
        </div>

        <%!-- Recent Recipes --%>
        <div class="flex items-center justify-between mb-4">
          <h2 class="text-base font-semibold text-base-content">Recent Recipes</h2>
          <.link navigate={~p"/recipes"} class="text-sm text-primary hover:text-primary/80 font-medium transition-colors">
            View all →
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

        <div class="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
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
            <div class="p-3">
              <h3 class="font-semibold text-sm text-base-content group-hover:text-primary transition-colors leading-snug truncate">
                {recipe.title}
              </h3>
              <div class="flex items-center gap-3 mt-1">
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

        <%!-- Mobile: This Week summary --%>
        <div class="lg:hidden rounded-2xl border border-base-300/50 bg-base-100 p-5 mb-6">
          <div class="flex items-center justify-between mb-3">
            <h2 class="font-semibold text-base-content">This Week</h2>
            <.link navigate={~p"/planner?week=#{Date.to_iso8601(@week_start)}"} class="text-xs text-primary font-medium">View →</.link>
          </div>
          <div class="space-y-1.5">
            <div :for={day_num <- 1..7} class="flex items-center justify-between">
              <span class="text-xs text-base-content/50 w-8">{day_name(day_num)}</span>
              <div class="flex-1 flex justify-end">
                <%= if Map.has_key?(@week_map, day_num) do %>
                  <span class="text-xs text-primary font-medium">{length(Map.get(@week_map, day_num))} meal{if length(Map.get(@week_map, day_num)) != 1, do: "s", else: ""}</span>
                <% else %>
                  <span class="text-xs text-base-content/30">Empty</span>
                <% end %>
              </div>
            </div>
          </div>
        </div>

      </div>

      <%!-- Right panel: This Week (fixed, full-height, desktop only) --%>
      <aside class="hidden lg:flex lg:flex-col lg:fixed lg:right-0 lg:top-0 lg:bottom-0 lg:w-72 border-l border-base-300/50 bg-base-100 z-20 overflow-y-auto">
        <div class="p-6 flex-1">
          <div class="flex items-center justify-between mb-1">
            <h2 class="text-base font-semibold text-base-content">This Week</h2>
            <.link navigate={~p"/planner?week=#{Date.to_iso8601(@week_start)}"} class="text-base-content/40 hover:text-base-content transition-colors">
              <.icon name="hero-calendar-days" class="size-4" />
            </.link>
          </div>
          <p class="text-xs text-base-content/40 mb-5">
            {Calendar.strftime(@week_start, "%b %-d")} – {Calendar.strftime(Date.add(@week_start, 6), "%b %-d, %Y")}
          </p>

          <%!-- Progress --%>
          <div class="mb-5 p-3 rounded-xl bg-base-200/60">
            <div class="flex items-center justify-between text-sm mb-2">
              <span class="text-base-content/70 text-xs">{@filled_slots} of {@total_slots} meals planned</span>
              <span class="text-primary font-semibold text-xs">{round(@filled_slots / @total_slots * 100)}%</span>
            </div>
            <div class="h-1.5 rounded-full bg-base-300/50 overflow-hidden">
              <div
                class="h-full rounded-full bg-gradient-to-r from-primary to-secondary transition-all duration-500"
                style={"width: #{@filled_slots / @total_slots * 100}%"}
              ></div>
            </div>
          </div>

          <%!-- Days list --%>
          <div class="space-y-1">
            <div :for={day_num <- 1..7} class="py-2 border-b border-base-300/30 last:border-0">
              <div class="flex items-center justify-between">
                <span class="text-xs font-semibold tracking-wider uppercase text-base-content/40">{day_name(day_num)}</span>
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
        </div>

        <%!-- Bottom stats --%>
        <div class="border-t border-base-300/50 px-6 py-4 grid grid-cols-2 gap-4">
          <div class="text-center">
            <div class="text-2xl font-black text-primary">{@recipe_count}</div>
            <div class="text-xs text-base-content/40">Recipes</div>
          </div>
          <div class="text-center">
            <div class="text-2xl font-black text-primary">{@filled_slots}</div>
            <div class="text-xs text-base-content/40">This week</div>
          </div>
        </div>
      </aside>

    </div>
    """
  end
end

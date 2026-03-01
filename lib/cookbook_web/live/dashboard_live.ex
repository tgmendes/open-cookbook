defmodule CookbookWeb.DashboardLive do
  use CookbookWeb, :live_view

  alias Cookbook.Recipes
  alias Cookbook.Planner

  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    recipe_count = length(Recipes.list_recipes(user.id))

    week_start = Planner.normalize_to_monday(Date.utc_today())
    {:ok, plan} = Planner.get_or_create_plan_for_week(user.id, week_start)

    filled_slots = length(plan.entries)
    total_slots = 14

    {:ok,
     assign(socket,
       page_title: "Dashboard",
       recipe_count: recipe_count,
       week_start: week_start,
       filled_slots: filled_slots,
       total_slots: total_slots,
       plan: plan
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl">
      <%!-- Hero greeting --%>
      <div class="relative overflow-hidden rounded-2xl bg-gradient-to-br from-primary via-primary/90 to-secondary p-8 mb-8 shadow-lg">
        <div class="absolute inset-0 bg-[radial-gradient(circle_at_top_right,rgba(255,255,255,0.15),transparent_70%)]"></div>
        <div class="relative">
          <h1 class="text-2xl font-bold text-primary-content">Welcome back</h1>
          <p class="text-primary-content/70 mt-1">Here's your kitchen at a glance</p>
        </div>
      </div>

      <%!-- Stat cards --%>
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-3 mb-8">
        <div class="group relative overflow-hidden rounded-xl bg-base-200 border border-base-300/50 p-5 hover:border-primary/30 transition-all duration-300">
          <div class="flex items-center justify-between">
            <div>
              <div class="text-xs font-semibold uppercase tracking-wider text-base-content/40">Recipes</div>
              <div class="text-3xl font-black mt-1 text-base-content">{@recipe_count}</div>
            </div>
            <div class="flex items-center justify-center w-12 h-12 rounded-xl bg-primary/15 group-hover:bg-primary/25 transition-colors">
              <.icon name="hero-book-open-solid" class="size-6 text-primary" />
            </div>
          </div>
        </div>

        <div class="group relative overflow-hidden rounded-xl bg-base-200 border border-base-300/50 p-5 hover:border-secondary/30 transition-all duration-300">
          <div class="flex items-center justify-between">
            <div>
              <div class="text-xs font-semibold uppercase tracking-wider text-base-content/40">This Week</div>
              <div class="text-3xl font-black mt-1 text-base-content">
                {@filled_slots}<span class="text-lg font-normal text-base-content/30">/{@total_slots}</span>
              </div>
            </div>
            <div class="flex items-center justify-center w-12 h-12 rounded-xl bg-secondary/15 group-hover:bg-secondary/25 transition-colors">
              <.icon name="hero-calendar-days-solid" class="size-6 text-secondary" />
            </div>
          </div>
          <%!-- Mini progress bar --%>
          <div class="mt-3 h-1.5 rounded-full bg-base-300/50 overflow-hidden">
            <div class="h-full rounded-full bg-gradient-to-r from-primary to-secondary transition-all duration-500" style={"width: #{@filled_slots / @total_slots * 100}%"}></div>
          </div>
        </div>

        <div class="group relative overflow-hidden rounded-xl bg-base-200 border border-base-300/50 p-5 hover:border-accent/30 transition-all duration-300">
          <div class="flex items-center justify-between">
            <div>
              <div class="text-xs font-semibold uppercase tracking-wider text-base-content/40">Week of</div>
              <div class="text-3xl font-black mt-1 text-base-content">{Calendar.strftime(@week_start, "%b %d")}</div>
            </div>
            <div class="flex items-center justify-center w-12 h-12 rounded-xl bg-accent/15 group-hover:bg-accent/25 transition-colors">
              <.icon name="hero-clock-solid" class="size-6 text-accent" />
            </div>
          </div>
        </div>
      </div>

      <%!-- Quick actions --%>
      <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/40 mb-3">Quick Actions</h2>
      <div class="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <.link
          navigate={~p"/planner?week=#{Date.to_iso8601(@week_start)}"}
          class="group flex items-start gap-4 p-5 rounded-xl bg-base-200 border border-base-300/50 hover:border-primary/30 hover:bg-base-200/80 transition-all duration-300"
        >
          <div class="flex items-center justify-center w-11 h-11 rounded-xl bg-gradient-to-br from-primary/20 to-primary/10 shrink-0 group-hover:from-primary/30 group-hover:to-primary/20 transition-colors">
            <.icon name="hero-calendar-days-solid" class="size-5 text-primary" />
          </div>
          <div>
            <h3 class="font-semibold text-base-content group-hover:text-primary transition-colors">Plan this week</h3>
            <p class="mt-0.5 text-sm text-base-content/50">Assign recipes to meals</p>
          </div>
        </.link>

        <.link
          navigate={~p"/recipes/new"}
          class="group flex items-start gap-4 p-5 rounded-xl bg-base-200 border border-base-300/50 hover:border-secondary/30 hover:bg-base-200/80 transition-all duration-300"
        >
          <div class="flex items-center justify-center w-11 h-11 rounded-xl bg-gradient-to-br from-secondary/20 to-secondary/10 shrink-0 group-hover:from-secondary/30 group-hover:to-secondary/20 transition-colors">
            <.icon name="hero-plus-circle-solid" class="size-5 text-secondary" />
          </div>
          <div>
            <h3 class="font-semibold text-base-content group-hover:text-secondary transition-colors">Add recipe</h3>
            <p class="mt-0.5 text-sm text-base-content/50">Manual, URL, or AI</p>
          </div>
        </.link>

        <.link
          navigate={~p"/planner/shopping?week=#{Date.to_iso8601(@week_start)}"}
          class="group flex items-start gap-4 p-5 rounded-xl bg-base-200 border border-base-300/50 hover:border-accent/30 hover:bg-base-200/80 transition-all duration-300"
        >
          <div class="flex items-center justify-center w-11 h-11 rounded-xl bg-gradient-to-br from-accent/20 to-accent/10 shrink-0 group-hover:from-accent/30 group-hover:to-accent/20 transition-colors">
            <.icon name="hero-shopping-cart-solid" class="size-5 text-accent" />
          </div>
          <div>
            <h3 class="font-semibold text-base-content group-hover:text-accent transition-colors">Shopping list</h3>
            <p class="mt-0.5 text-sm text-base-content/50">Ingredients for the week</p>
          </div>
        </.link>
      </div>
    </div>
    """
  end
end

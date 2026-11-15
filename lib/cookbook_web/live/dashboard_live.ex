defmodule CookbookWeb.DashboardLive do
  use CookbookWeb, :live_view
  alias Cookbook.{Recipes, Planner}

  def mount(_params, _session, socket) do
    recipes = Recipes.list_recipes(socket.assigns.current_user.id)

    {:ok, plan} =
      Planner.get_or_create_plan_for_week(socket.assigns.current_user.id, Date.utc_today())

    days =
      for day <- 1..7,
          do: %{
            id: day,
            name: Planner.short_day_name(day),
            entries: Enum.filter(plan.entries, &(&1.day_of_week == day))
          }

    {:ok,
     socket
     |> assign(
       page_title: "Today",
       recipe_count: length(recipes),
       filled_slots: plan.entries |> Enum.uniq_by(&{&1.day_of_week, &1.meal_type}) |> length()
     )
     |> stream(:recent, Enum.take(recipes, 4))
     |> stream(:days, days), layout: false}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app {assigns}>
      <div class="space-y-8">
        <header class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <p class="eyebrow">{Calendar.strftime(Date.utc_today(), "%A, %B %-d")}</p>
            <h1 class="mt-2 text-4xl">A good day to cook.</h1>
            <p class="mt-2 text-muted">A little planning. Something delicious.</p>
          </div>
          <.link navigate="/recipes/new" class="action action-primary">
            <.icon name="hero-plus" class="size-5" />New recipe
          </.link>
        </header>
        <div class="flex flex-wrap gap-2.5">
          <.link navigate="/recipes/new?mode=url" class="action">
            <.icon name="hero-link" class="size-4" />Import from link
          </.link>
          <.link navigate="/recipes/new?mode=generate" class="action"><.icon
            name="hero-sparkles"
            class="size-4"
          />Describe it</.link><.link navigate="/planner" class="action"><.icon
            name="hero-calendar-days"
            class="size-4"
          />Plan this week</.link><.link navigate="/planner/shopping" class="action"><.icon
            name="hero-shopping-cart"
            class="size-4"
          />Shopping list</.link>
        </div>
        <div class="grid items-start gap-7 xl:grid-cols-[minmax(0,1fr)_300px]">
          <div class="min-w-0 space-y-8">
            <section id="today-dinner" class="surface overflow-hidden">
              <div class="flex items-center gap-3 bg-peach px-6 py-4 text-peach-ink">
                <.icon name="hero-fire" class="size-6" />
                <h2 class="text-lg">On the plan tonight</h2>
              </div>
              <div class="space-y-4 p-6">
                <%= if @navigation.tonight do %>
                  <h3 class="text-2xl">{@navigation.tonight.title}</h3>
                  <p class="text-sm text-muted">
                    <span :if={@navigation.tonight.total_time_minutes}>
                      {"#{@navigation.tonight.total_time_minutes} min · "}
                    </span>
                    <span :if={@navigation.tonight.servings}>Serves {@navigation.tonight.servings}</span>
                  </p>
                  <.link
                    navigate={~p"/recipes/#{@navigation.tonight.id}/cook"}
                    class="action action-primary"
                  >
                    Start cooking <.icon name="hero-arrow-right" class="size-5" />
                  </.link>
                <% else %>
                  <h3 class="text-2xl">What's for dinner?</h3>
                  <p class="text-muted">Give yourself something to look forward to.</p>
                  <.link navigate="/planner" class="action">Choose tonight's meal</.link>
                <% end %>
              </div>
            </section>
            <section class="space-y-4" aria-label="Recent recipes">
              <div class="flex items-center justify-between">
                <h2 class="text-xl">Recently added to your kitchen</h2>
                <.link navigate="/recipes" class="inline-flex min-h-11 items-center text-sm underline">
                  View all
                </.link>
              </div>
              <p :if={@recipe_count == 0} class="surface p-8 text-center text-muted">
                Your collection starts with your first recipe.
              </p>
              <div id="recent-recipes" phx-update="stream" class="grid gap-4 sm:grid-cols-2">
                <.link
                  :for={{id, recipe} <- @streams.recent}
                  id={id}
                  navigate={~p"/recipes/#{recipe.id}"}
                  class="surface group overflow-hidden transition-shadow hover:shadow-md"
                >
                  <div class="flex h-36 items-center justify-center overflow-hidden bg-butter">
                    <img
                      :if={recipe.image_url}
                      src={recipe.image_url}
                      alt=""
                      class="size-full object-cover"
                    /><.icon :if={!recipe.image_url} name="hero-cake" class="size-12 text-butter-ink" />
                  </div>
                  <div class="space-y-2 p-4">
                    <h3 class="text-lg group-hover:underline">{recipe.title}</h3>
                    <p :if={recipe.total_time_minutes} class="text-sm text-muted">
                      {recipe.total_time_minutes} min
                    </p>
                  </div>
                </.link>
              </div>
            </section>
          </div>
          <aside class="surface space-y-5 p-6" aria-label="This week">
            <div class="flex items-center justify-between">
              <h2 class="text-xl">This week</h2>
              <.link navigate="/planner" aria-label="Open meal plan" class="action size-11 !p-0">
                <.icon name="hero-calendar-days" class="size-5" />
              </.link>
            </div>
            <p class="text-sm text-muted">{@filled_slots} of 14 meals planned</p>
            <div class="h-2 overflow-hidden rounded-full bg-base-300">
              <div class="h-full bg-primary" style={"width: #{@filled_slots / 14 * 100}%"}></div>
            </div>
            <div id="dashboard-week" phx-update="stream" class="divide-y divide-base-300">
              <div :for={{id, day} <- @streams.days} id={id} class="flex items-start gap-4 py-3">
                <span class="w-8 text-sm font-bold text-muted">{day.name}</span>
                <div class="min-w-0 flex-1">
                  <p :if={day.entries == []} class="text-sm text-muted">Room for something good</p>
                  <p :for={entry <- day.entries} class="text-sm">{entry.recipe.title}</p>
                </div>
              </div>
            </div>
            <div class="flex items-center justify-between border-t border-base-300 pt-5 text-sm">
              <span class="text-muted">Your collection</span><span class="font-bold">{@recipe_count} recipes</span>
            </div>
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

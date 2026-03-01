defmodule CookbookWeb.PlannerLive do
  use CookbookWeb, :live_view

  alias Cookbook.Planner
  alias Cookbook.Recipes

  def mount(params, _session, socket) do
    week_start =
      case params["week"] do
        nil -> Planner.normalize_to_monday(Date.utc_today())
        date_str -> Date.from_iso8601!(date_str) |> Planner.normalize_to_monday()
      end

    {:ok, plan} = Planner.get_or_create_plan_for_week(socket.assigns.current_user.id, week_start)
    nav = Planner.week_navigation(week_start)
    recipes = Recipes.list_recipes(socket.assigns.current_user.id)

    {:ok,
     assign(socket,
       plan: plan,
       week_start: week_start,
       nav: nav,
       recipes: recipes,
       page_title: "Meal Planner",
       picker: nil,
       search: "",
       ai_loading: false
     )}
  end

  def handle_params(params, _uri, socket) do
    week_start =
      case params["week"] do
        nil -> Planner.normalize_to_monday(Date.utc_today())
        date_str -> Date.from_iso8601!(date_str) |> Planner.normalize_to_monday()
      end

    {:ok, plan} = Planner.get_or_create_plan_for_week(socket.assigns.current_user.id, week_start)
    nav = Planner.week_navigation(week_start)

    {:noreply, assign(socket, plan: plan, week_start: week_start, nav: nav)}
  end

  def handle_event("open_picker", %{"day" => day, "meal" => meal}, socket) do
    {:noreply, assign(socket, picker: %{day: String.to_integer(day), meal: meal}, search: "")}
  end

  def handle_event("close_picker", _params, socket) do
    {:noreply, assign(socket, picker: nil, search: "")}
  end

  def handle_event("search_recipes", %{"search" => search}, socket) do
    {:noreply, assign(socket, search: search)}
  end

  def handle_event("assign_recipe", %{"recipe-id" => recipe_id}, socket) do
    picker = socket.assigns.picker

    {:ok, _entry} =
      Planner.add_entry(socket.assigns.plan, %{
        day_of_week: picker.day,
        meal_type: String.to_existing_atom(picker.meal),
        recipe_id: recipe_id
      })

    {:ok, plan} =
      Planner.get_or_create_plan_for_week(
        socket.assigns.current_user.id,
        socket.assigns.week_start
      )

    {:noreply, assign(socket, plan: plan, picker: nil, search: "")}
  end

  def handle_event("remove_entry", %{"entry-id" => entry_id}, socket) do
    {:ok, _} = Planner.remove_entry(entry_id)

    {:ok, plan} =
      Planner.get_or_create_plan_for_week(
        socket.assigns.current_user.id,
        socket.assigns.week_start
      )

    {:noreply, assign(socket, plan: plan)}
  end

  def handle_event("suggest_plan", _params, socket) do
    self_pid = self()
    recipes = socket.assigns.recipes
    plan = socket.assigns.plan

    Task.start(fn ->
      result = Cookbook.AI.suggest_weekly_plan(recipes)
      send(self_pid, {:ai_plan_result, result, plan.id})
    end)

    {:noreply, assign(socket, ai_loading: true)}
  end

  def handle_info({:ai_plan_result, {:ok, data}, plan_id}, socket) do
    plan = socket.assigns.plan

    if plan.id == plan_id do
      entries = data["plan"] || []

      for entry <- entries do
        Planner.add_entry(plan, %{
          day_of_week: entry["day_of_week"],
          meal_type: String.to_existing_atom(entry["meal_type"]),
          recipe_id: entry["recipe_id"]
        })
      end

      {:ok, updated_plan} =
        Planner.get_or_create_plan_for_week(
          socket.assigns.current_user.id,
          socket.assigns.week_start
        )

      {:noreply,
       socket
       |> assign(plan: updated_plan, ai_loading: false)
       |> put_flash(:info, "AI plan applied!")}
    else
      {:noreply, assign(socket, ai_loading: false)}
    end
  end

  def handle_info({:ai_plan_result, {:error, _reason}, _plan_id}, socket) do
    {:noreply,
     socket
     |> assign(ai_loading: false)
     |> put_flash(:error, "AI plan generation failed. Please try again.")}
  end

  defp entries_for(plan, day, meal) do
    (plan.entries || [])
    |> Enum.filter(&(&1.day_of_week == day && &1.meal_type == meal))
    |> Enum.sort_by(& &1.position)
  end

  defp filtered_recipes(recipes, search) do
    case search do
      "" -> recipes
      nil -> recipes
      term ->
        term = String.downcase(term)
        Enum.filter(recipes, fn r -> String.contains?(String.downcase(r.title), term) end)
    end
  end

  defp is_today?(week_start, day) do
    Date.add(week_start, day - 1) == Date.utc_today()
  end

  def render(assigns) do
    ~H"""
    <div>
      <.header>
        Meal Planner
        <:subtitle>
          Week of {Calendar.strftime(@week_start, "%B %d, %Y")}
        </:subtitle>
        <:actions>
          <div class="flex gap-2">
            <.button navigate={~p"/planner/shopping?week=#{Date.to_iso8601(@week_start)}"}>
              <.icon name="hero-shopping-cart" class="size-4 mr-1" /> Shopping List
            </.button>
            <.button phx-click="suggest_plan" disabled={@ai_loading || @recipes == []} variant="primary">
              <.icon name="hero-sparkles" class="size-4 mr-1" />
              {if @ai_loading, do: "Generating...", else: "Suggest Plan (AI)"}
            </.button>
          </div>
        </:actions>
      </.header>

      <%!-- Week navigation --%>
      <div class="flex items-center justify-center gap-3 mt-4 mb-6">
        <.link
          navigate={~p"/planner?week=#{Date.to_iso8601(@nav.prev)}"}
          class="flex items-center justify-center w-9 h-9 rounded-full border border-base-300/50 bg-base-200 hover:border-primary/30 hover:text-primary transition-all duration-200"
        >
          <.icon name="hero-chevron-left" class="size-4" />
        </.link>
        <.link
          navigate={~p"/planner?week=#{Date.to_iso8601(Planner.normalize_to_monday(Date.utc_today()))}"}
          class="px-4 py-1.5 rounded-full border border-base-300/50 bg-base-200 text-sm font-medium hover:border-primary/30 hover:text-primary transition-all duration-200"
        >
          Today
        </.link>
        <.link
          navigate={~p"/planner?week=#{Date.to_iso8601(@nav.next)}"}
          class="flex items-center justify-center w-9 h-9 rounded-full border border-base-300/50 bg-base-200 hover:border-primary/30 hover:text-primary transition-all duration-200"
        >
          <.icon name="hero-chevron-right" class="size-4" />
        </.link>
      </div>

      <%!-- Week grid --%>
      <div class="grid grid-cols-1 md:grid-cols-7 gap-2">
        <div
          :for={day <- 1..7}
          class={[
            "rounded-xl border bg-base-200 overflow-hidden transition-all duration-300",
            is_today?(@week_start, day) && "border-primary ring-2 ring-primary/20" || "border-base-300/50 hover:border-base-300"
          ]}
        >
          <%!-- Day header --%>
          <div class={[
            "text-center py-2 border-b",
            is_today?(@week_start, day) && "bg-primary/5 border-primary/20" || "bg-base-100 border-base-200"
          ]}>
            <div class={[
              "text-xs font-medium uppercase tracking-wider",
              is_today?(@week_start, day) && "text-primary" || "text-base-content/50"
            ]}>
              {Planner.day_name(day)}
            </div>
            <div class={[
              "text-2xl font-bold",
              is_today?(@week_start, day) && "text-primary" || "text-base-content"
            ]}>
              {Calendar.strftime(Date.add(@week_start, day - 1), "%d")}
            </div>
          </div>

          <%!-- Meals --%>
          <div class="p-2">
            <div :for={meal <- [:lunch, :dinner]} class="mb-3 last:mb-0">
              <div class="text-[10px] font-semibold text-base-content/40 uppercase tracking-wider mb-1">
                {meal}
              </div>
              <div :for={entry <- entries_for(@plan, day, meal)} class="flex items-center gap-1 mb-1 group">
                <.link navigate={~p"/recipes/#{entry.recipe.id}"} class="text-xs hover:text-primary flex-1 truncate transition-colors">
                  {entry.recipe.title}
                </.link>
                <button
                  phx-click="remove_entry"
                  phx-value-entry-id={entry.id}
                  class="text-base-content/20 hover:text-error text-xs opacity-0 group-hover:opacity-100 transition-opacity"
                >
                  <.icon name="hero-x-mark" class="size-3.5" />
                </button>
              </div>
              <button
                phx-click="open_picker"
                phx-value-day={day}
                phx-value-meal={meal}
                class="text-xs text-primary/60 hover:text-primary w-full text-left transition-colors"
              >
                + add
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Recipe picker modal --%>
      <div :if={@picker} class="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm" phx-click="close_picker">
        <div class="bg-base-200 rounded-2xl shadow-2xl p-6 w-full max-w-md max-h-[80vh] overflow-y-auto" phx-click-away="close_picker">
          <div class="flex items-center justify-between mb-4">
            <h3 class="font-semibold text-lg">
              {Planner.day_name(@picker.day)} - {String.capitalize(to_string(@picker.meal))}
            </h3>
            <button phx-click="close_picker" class="flex items-center justify-center w-8 h-8 rounded-full hover:bg-base-300 transition-colors">
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <form phx-change="search_recipes" class="mb-4">
            <div class="relative">
              <span class="absolute left-3 top-1/2 -translate-y-1/2 text-base-content/40 pointer-events-none">
                <.icon name="hero-magnifying-glass" class="size-4" />
              </span>
              <input
                type="search"
                name="search"
                value={@search}
                placeholder="Search recipes..."
                class="w-full input pl-10"
                phx-debounce="200"
              />
            </div>
          </form>

          <div :if={@recipes == []} class="text-center text-base-content/50 py-8">
            <p>No recipes yet.</p>
            <.link navigate={~p"/recipes/new"} class="text-primary text-sm mt-1 inline-block">Create one</.link>
          </div>

          <div class="space-y-1">
            <button
              :for={recipe <- filtered_recipes(@recipes, @search)}
              phx-click="assign_recipe"
              phx-value-recipe-id={recipe.id}
              class="w-full flex items-center gap-3 text-left hover:bg-base-300/50 rounded-lg px-3 py-2.5 transition-colors"
            >
              <span class="font-medium text-sm">{recipe.title}</span>
              <span :if={recipe.total_time_minutes} class="text-base-content/40 text-xs ml-auto">
                {recipe.total_time_minutes} min
              </span>
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end

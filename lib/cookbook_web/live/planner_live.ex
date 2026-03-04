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

    today_dow = Date.day_of_week(Date.utc_today())
    current_week_monday = Planner.normalize_to_monday(Date.utc_today())
    selected_day = if week_start == current_week_monday, do: today_dow, else: 1

    {:ok,
     assign(socket,
       plan: plan,
       week_start: week_start,
       nav: nav,
       recipes: recipes,
       page_title: "Meal Planner",
       picker: nil,
       search: "",
       ai_loading: false,
       selected_day: selected_day
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

    today_dow = Date.day_of_week(Date.utc_today())
    current_week_monday = Planner.normalize_to_monday(Date.utc_today())
    selected_day = if week_start == current_week_monday, do: today_dow, else: 1

    {:noreply, assign(socket, plan: plan, week_start: week_start, nav: nav, selected_day: selected_day)}
  end

  def handle_event("select_day", %{"day" => day}, socket) do
    {:noreply, assign(socket, selected_day: String.to_integer(day))}
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

  defp day_has_meals?(plan, day) do
    Enum.any?(plan.entries || [], &(&1.day_of_week == day))
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

      <%!-- MOBILE: Day strip + single-day detail (visible below md) --%>
      <div class="md:hidden">
        <.day_strip
          week_start={@week_start}
          selected_day={@selected_day}
          plan={@plan}
        />
        <.day_detail
          week_start={@week_start}
          selected_day={@selected_day}
          plan={@plan}
        />
      </div>

      <%!-- DESKTOP: 7-column calendar grid (visible at md+) --%>
      <div class="hidden md:block overflow-x-auto">
        <div class="grid grid-cols-7 gap-2 min-w-[700px]">
          <div :for={day <- 1..7} class="flex flex-col">
            <%!-- Day header --%>
            <div class={[
              "rounded-t-xl px-2 py-3 text-center",
              if(is_today?(@week_start, day),
                do: "bg-primary text-primary-content",
                else: "bg-base-200"
              )
            ]}>
              <span class={[
                "block text-[10px] font-semibold uppercase tracking-wider",
                if(is_today?(@week_start, day), do: "text-primary-content/70", else: "text-base-content/50")
              ]}>
                {Planner.short_day_name(day)}
              </span>
              <span class="block text-xl font-bold leading-tight mt-0.5">
                {Calendar.strftime(Date.add(@week_start, day - 1), "%d")}
              </span>
            </div>
            <%!-- Meal slots --%>
            <div class="border border-t-0 border-base-300/50 rounded-b-xl p-1.5 flex flex-col gap-2 flex-1 bg-base-100 min-h-[160px]">
              <div :for={meal <- [:lunch, :dinner]}>
                <div class="text-[9px] font-semibold uppercase tracking-wider text-base-content/40 mb-1 px-0.5">
                  {meal}
                </div>
                <%!-- Entries --%>
                <div
                  :for={entry <- entries_for(@plan, day, meal)}
                  class="group relative rounded-lg overflow-hidden border border-base-300/30 bg-base-200/50 mb-1"
                >
                  <div class="aspect-video overflow-hidden bg-base-200">
                    <img
                      :if={entry.recipe.image_url}
                      src={entry.recipe.image_url}
                      alt={entry.recipe.title}
                      class="w-full h-full object-cover"
                    />
                    <div
                      :if={!entry.recipe.image_url}
                      class="w-full h-full bg-gradient-to-br from-primary/5 to-secondary/5 flex items-center justify-center"
                    >
                      <.icon name="hero-book-open" class="size-4 text-primary/20" />
                    </div>
                  </div>
                  <div class="px-1.5 py-1">
                    <.link
                      navigate={~p"/recipes/#{entry.recipe.id}"}
                      class="text-[11px] font-medium text-base-content hover:text-primary transition-colors line-clamp-2 block leading-snug"
                    >
                      {entry.recipe.title}
                    </.link>
                  </div>
                  <button
                    phx-click="remove_entry"
                    phx-value-entry-id={entry.id}
                    class="absolute top-1 right-1 hidden group-hover:flex items-center justify-center w-5 h-5 rounded-full bg-base-100/90 text-base-content/40 hover:text-error transition-colors shadow-sm"
                  >
                    <.icon name="hero-x-mark" class="size-3" />
                  </button>
                </div>
                <%!-- Add button --%>
                <button
                  phx-click="open_picker"
                  phx-value-day={day}
                  phx-value-meal={meal}
                  class="w-full flex items-center justify-center gap-1 rounded-lg border border-dashed border-base-300/40 hover:border-primary/40 text-base-content/20 hover:text-primary py-1.5 transition-colors text-[10px]"
                >
                  <.icon name="hero-plus" class="size-2.5" />
                  Add
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Recipe picker modal (unchanged) --%>
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

  # ── Mobile Components ──────────────────────────────────────────────

  defp day_strip(assigns) do
    ~H"""
    <div class="flex gap-1.5 overflow-x-auto pb-3 px-1 -mx-1 scrollbar-none">
      <button
        :for={day <- 1..7}
        phx-click="select_day"
        phx-value-day={day}
        class={[
          "flex flex-col items-center flex-shrink-0 w-12 py-2 rounded-xl border transition-all duration-200",
          cond do
            day == @selected_day && is_today?(@week_start, day) ->
              "bg-primary text-primary-content border-primary ring-2 ring-primary/20"
            day == @selected_day ->
              "bg-primary text-primary-content border-primary"
            is_today?(@week_start, day) ->
              "bg-base-200 border-primary/40 text-primary"
            true ->
              "bg-base-200 border-base-300/50 text-base-content"
          end
        ]}
      >
        <span class="text-[10px] font-semibold uppercase tracking-wider">
          {Planner.short_day_name(day)}
        </span>
        <span class="text-lg font-bold leading-tight">
          {Calendar.strftime(Date.add(@week_start, day - 1), "%d")}
        </span>
        <span
          :if={day_has_meals?(@plan, day)}
          class={[
            "w-1.5 h-1.5 rounded-full mt-0.5",
            if(day == @selected_day, do: "bg-primary-content/60", else: "bg-primary/60")
          ]}
        />
      </button>
    </div>
    """
  end

  defp day_detail(assigns) do
    assigns = assign(assigns, :day, assigns.selected_day)

    ~H"""
    <div class="mt-2 space-y-3">
      <div class="text-sm font-semibold text-base-content/60">
        {Planner.day_name(@day)}, {Calendar.strftime(Date.add(@week_start, @day - 1), "%B %d")}
      </div>

      <div :for={meal <- [:lunch, :dinner]} class="space-y-2">
        <div class="text-xs font-semibold text-base-content/40 uppercase tracking-wider">
          {meal}
        </div>

        <%!-- Existing entries --%>
        <div
          :for={entry <- entries_for(@plan, @day, meal)}
          class="flex items-center gap-3 rounded-xl border border-base-300/50 bg-base-200 px-4 py-3"
        >
          <.link navigate={~p"/recipes/#{entry.recipe.id}"} class="text-sm font-medium hover:text-primary flex-1 transition-colors">
            {entry.recipe.title}
          </.link>
          <button
            phx-click="remove_entry"
            phx-value-entry-id={entry.id}
            class="flex items-center justify-center w-8 h-8 rounded-full text-base-content/30 hover:text-error hover:bg-error/10 transition-colors"
          >
            <.icon name="hero-x-mark" class="size-4" />
          </button>
        </div>

        <%!-- Add button --%>
        <button
          :if={entries_for(@plan, @day, meal) == []}
          phx-click="open_picker"
          phx-value-day={@day}
          phx-value-meal={meal}
          class="w-full flex items-center justify-center gap-2 rounded-xl border-2 border-dashed border-base-300/50 hover:border-primary/40 text-base-content/30 hover:text-primary py-4 transition-colors"
        >
          <.icon name="hero-plus" class="size-4" />
          <span class="text-sm">Add {meal}</span>
        </button>
        <button
          :if={entries_for(@plan, @day, meal) != []}
          phx-click="open_picker"
          phx-value-day={@day}
          phx-value-meal={meal}
          class="w-full flex items-center justify-center gap-1 text-xs text-primary/50 hover:text-primary py-1 transition-colors"
        >
          <.icon name="hero-plus" class="size-3" />
          <span>Add another</span>
        </button>
      </div>
    </div>
    """
  end

end

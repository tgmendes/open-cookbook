defmodule CookbookWeb.PlannerLive do
  use CookbookWeb, :live_view
  alias Cookbook.{Planner, Recipes, AI}

  def mount(_params, _session, socket) do
    socket = stream_configure(socket, :meal_rows, dom_id: fn row -> "meal-row-#{row.id}" end)

    {:ok,
     assign(socket,
       page_title: "Meal plan",
       selected_day: Date.day_of_week(Date.utc_today()),
       selected_meal: :dinner,
       search: "",
       quick: false,
       ai_loading: false,
       search_form: to_form(%{"search" => ""})
     ), layout: false}
  end

  def handle_params(params, _uri, socket) do
    week_start = Planner.week_from_param(params["week"])

    day =
      if week_start == Planner.normalize_to_monday(Date.utc_today()),
        do: Date.day_of_week(Date.utc_today()),
        else: 1

    {:noreply,
     socket
     |> assign(
       week_start: week_start,
       nav: Planner.week_navigation(week_start),
       selected_day: day
     )
     |> refresh()
     |> refresh_tray()}
  end

  def handle_event("open_picker", %{"day" => day, "meal" => meal}, socket) do
    case {Integer.parse(day), meal} do
      {{day, ""}, meal} when day in 1..7 and meal in ["lunch", "dinner"] ->
        {:noreply, assign(socket, selected_day: day, selected_meal: meal_type(meal))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("select_slot", %{"slot" => %{"day" => day, "meal" => meal}}, socket),
    do: handle_event("open_picker", %{"day" => day, "meal" => meal}, socket)

  def handle_event("search_recipes", %{"search" => search}, socket),
    do:
      {:noreply,
       socket
       |> assign(search: search, search_form: to_form(%{"search" => search}))
       |> refresh_tray()}

  def handle_event("quick", _, socket),
    do: {:noreply, socket |> assign(quick: !socket.assigns.quick) |> refresh_tray()}

  def handle_event("assign_recipe", %{"recipe-id" => id}, socket) do
    if Enum.any?(Recipes.list_recipes(socket.assigns.current_user.id), &(&1.id == id)) do
      case Planner.add_entry(socket.assigns.plan, %{
             day_of_week: socket.assigns.selected_day,
             meal_type: socket.assigns.selected_meal,
             recipe_id: id
           }) do
        {:ok, _} -> {:noreply, refresh(socket)}
        _ -> {:noreply, put_flash(socket, :error, "Couldn't add that recipe.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_entry", %{"entry-id" => id}, socket) do
    if Enum.any?(socket.assigns.plan.entries, &(&1.id == id)), do: Planner.remove_entry(id)
    {:noreply, refresh(socket)}
  end

  def handle_event("suggest_plan", _, socket) do
    if socket.assigns.ai_loading do
      {:noreply, socket}
    else
      recipes = Recipes.list_recipes(socket.assigns.current_user.id)
      plan_id = socket.assigns.plan.id

      {:noreply,
       socket
       |> assign(ai_loading: true)
       |> start_async({:suggest_plan, plan_id}, fn -> AI.suggest_weekly_plan(recipes) end)}
    end
  end

  def handle_async({:suggest_plan, plan_id}, {:ok, {:ok, data}}, socket) do
    if socket.assigns.plan.id == plan_id do
      Planner.fill_empty_slots(socket.assigns.plan, data["plan"] || [])

      {:noreply,
       socket
       |> assign(ai_loading: false)
       |> refresh()
       |> put_flash(:info, "Suggestions added to empty slots.")}
    else
      {:noreply, assign(socket, ai_loading: false)}
    end
  end

  def handle_async({:suggest_plan, _}, _, socket),
    do:
      {:noreply,
       socket
       |> assign(ai_loading: false)
       |> put_flash(:error, "Couldn't suggest meals. Your plan is unchanged.")}

  defp meal_type("lunch"), do: :lunch
  defp meal_type("dinner"), do: :dinner

  defp tone(id),
    do:
      Enum.at(
        [
          "bg-sage text-sage-ink",
          "bg-peach text-peach-ink",
          "bg-butter text-butter-ink",
          "bg-lavender text-lavender-ink",
          "bg-sky text-sky-ink",
          "bg-blush text-blush-ink"
        ],
        :erlang.phash2(id, 6)
      )

  defp refresh(socket) do
    {:ok, plan} =
      Planner.get_or_create_plan_for_week(
        socket.assigns.current_user.id,
        socket.assigns.week_start
      )

    slots = Enum.group_by(plan.entries, &{&1.day_of_week, &1.meal_type})

    rows =
      for meal <- [:lunch, :dinner],
          do: %{
            id: meal,
            slots: for(day <- 1..7, do: %{day: day, entries: Map.get(slots, {day, meal}, [])})
          }

    days =
      for day <- 1..7 do
        date = Date.add(socket.assigns.week_start, day - 1)

        %{
          number: day,
          date: date,
          today?: date == Date.utc_today(),
          past?: Date.compare(date, Date.utc_today()) == :lt
        }
      end

    socket
    |> assign(
      plan: plan,
      days: days,
      filled_count: map_size(slots),
      tip: Planner.cook_together_tip(plan),
      shopping_count:
        Enum.count(Planner.shopping_items(plan), &(&1.id not in plan.shopping_checked)),
      navigation: Planner.navigation_summary(socket.assigns.current_user.id)
    )
    |> stream(:meal_rows, rows, reset: true)
  end

  defp refresh_tray(socket) do
    recipes = Recipes.list_recipes(socket.assigns.current_user.id, search: socket.assigns.search)

    recipes =
      if socket.assigns.quick,
        do: Enum.filter(recipes, &(&1.total_time_minutes && &1.total_time_minutes <= 30)),
        else: recipes

    socket |> assign(tray_empty?: recipes == []) |> stream(:tray, recipes, reset: true)
  end

  def render(assigns) do
    assigns =
      assign(
        assigns,
        :slot_form,
        to_form(%{"day" => assigns.selected_day, "meal" => assigns.selected_meal}, as: :slot)
      )

    ~H"""
    <Layouts.app {assigns}>
      <div class="min-w-0 space-y-6">
        <header class="flex flex-wrap items-end justify-between gap-4">
          <div class="space-y-2.5">
            <h1 class="text-4xl">
              {if @week_start == Planner.normalize_to_monday(Date.utc_today()),
                do: "This week",
                else: "Meal plan"}
            </h1>
            <div class="flex items-center gap-2">
              <.link
                id="previous-week"
                patch={~p"/planner?week=#{Date.to_iso8601(@nav.prev)}"}
                aria-label="Previous week"
                class="action size-11 !rounded-full !p-0"
              >
                <.icon name="hero-chevron-left" class="size-5" />
              </.link>
              <span class="min-w-36 text-center font-bold">{Calendar.strftime(@week_start, "%-d %b")} – {Calendar.strftime(Date.add(@week_start, 6), "%-d %b")}</span><.link
                id="next-week"
                patch={~p"/planner?week=#{Date.to_iso8601(@nav.next)}"}
                aria-label="Next week"
                class="action size-11 !rounded-full !p-0"
              ><.icon name="hero-chevron-right" class="size-5" /></.link>
            </div>
          </div>
          <div class="flex flex-wrap gap-2.5">
            <button
              id="fill-slots"
              phx-click="suggest_plan"
              disabled={@ai_loading || @filled_count == 14 || @tray_empty?}
              class="action"
            >
              <.icon name="hero-sparkles" class="size-4" />{if @ai_loading,
                do: "Finding meals…",
                else: "Fill #{14 - @filled_count} empty slots"}
            </button>
            <.link
              navigate={~p"/planner/shopping?week=#{Date.to_iso8601(@week_start)}"}
              class="action action-primary"
            ><.icon name="hero-shopping-cart" class="size-4" />Shopping list · {@shopping_count} left</.link>
          </div>
        </header>
        <div id="plan-summary" class="flex flex-wrap gap-3">
          <section class="surface min-w-48 flex-1 space-y-2 !rounded-2xl px-4 py-3.5">
            <h2 class="font-body text-sm font-normal tracking-normal text-muted">Meals planned</h2>
            <div class="flex items-center gap-3">
              <span class="font-heading text-[22px] font-semibold">{@filled_count} of 14</span>
              <div class="h-2 flex-1 overflow-hidden rounded-full bg-base-300">
                <div
                  class="h-full rounded-full bg-primary"
                  style={"width: #{@filled_count / 14 * 100}%"}
                >
                </div>
              </div>
            </div>
          </section>
          <section class="min-w-40 flex-1 space-y-1 rounded-2xl bg-sage px-4 py-3.5 text-sage-ink">
            <h2 class="font-body text-sm font-normal tracking-normal">Lunches planned</h2>
            <p class="font-heading text-[22px] font-semibold">{plan_lunch_count(@plan)} lunches</p>
          </section>
          <section
            :if={@tip}
            id="cook-together-tip"
            class="flex basis-80 items-center gap-3 rounded-2xl bg-lavender px-4 py-3.5 text-sm leading-relaxed text-lavender-ink"
          >
            <.icon name="hero-light-bulb" class="size-6 shrink-0" />
            <p>
              <strong>Cook together on {@tip.day}:</strong> {@tip.recipe} simmers for {@tip.minutes} min — use that window to prep {@tip.other}.
            </p>
          </section>
        </div>
        <div class="flex min-w-0 flex-col items-start gap-6 xl:flex-row">
          <section
            id="week-calendar"
            aria-label="Week calendar"
            tabindex="0"
            class="w-full min-w-0 flex-1 overflow-x-auto pb-4"
          >
            <div class="min-w-[860px] space-y-2.5">
              <div class="grid grid-cols-[76px_repeat(7,minmax(0,1fr))] gap-2.5">
                <span></span>
                <div
                  :for={day <- @days}
                  class={[
                    "rounded-[14px] py-2.5 text-center",
                    cond do
                      day.today? -> "bg-primary text-primary-content"
                      day.past? -> "text-muted"
                      true -> "bg-base-200"
                    end
                  ]}
                >
                  <p class="text-xs font-bold tracking-wider uppercase">
                    {if day.today?, do: "Today", else: Planner.short_day_name(day.number)}
                  </p>
                  <p class="font-heading text-[22px] font-semibold">{day.date.day}</p>
                </div>
              </div>
              <div id="calendar-rows" phx-update="stream" class="space-y-2.5">
                <div
                  :for={{id, row} <- @streams.meal_rows}
                  id={id}
                  class="grid grid-cols-[76px_repeat(7,minmax(0,1fr))] gap-2.5"
                >
                  <h2 class="eyebrow self-center">{row.id}</h2>
                  <div
                    :for={slot <- row.slots}
                    id={"slot-#{slot.day}-#{row.id}"}
                    class={[
                      "flex min-h-[132px] flex-col gap-2 rounded-[14px]",
                      Date.compare(Date.add(@week_start, slot.day - 1), Date.utc_today()) == :lt &&
                        "opacity-60"
                    ]}
                  >
                    <article
                      :for={entry <- slot.entries}
                      class={[
                        "relative flex flex-1 flex-col gap-2 rounded-[14px] p-3",
                        tone(entry.recipe_id),
                        Date.add(@week_start, slot.day - 1) == Date.utc_today() &&
                          "ring-2 ring-primary"
                      ]}
                    >
                      <span class="pr-8 text-[11px] font-bold uppercase">{row.id}</span>
                      <h3 class="text-sm leading-snug">
                        <.link
                          navigate={~p"/recipes/#{entry.recipe_id}/cook"}
                          class="inline-flex min-h-11 items-center hover:underline"
                        >
                          {entry.recipe.title}
                        </.link>
                      </h3>
                      <p :if={entry.recipe.total_time_minutes} class="mt-auto text-xs">
                        {entry.recipe.total_time_minutes} min
                      </p>
                      <button
                        phx-click="remove_entry"
                        phx-value-entry-id={entry.id}
                        aria-label={"Remove #{entry.recipe.title}"}
                        class="absolute top-0 right-0 flex size-11 items-center justify-center rounded-xl hover:bg-base-200/40"
                      >
                        <.icon name="hero-x-mark" class="size-4" />
                      </button>
                    </article>
                    <button
                      id={"add-#{slot.day}-#{row.id}"}
                      phx-click={
                        JS.push("open_picker",
                          value: %{day: to_string(slot.day), meal: to_string(row.id)}
                        )
                        |> JS.focus(to: "#tray-search")
                      }
                      aria-label={"Add a meal for #{Planner.day_name(slot.day)} #{row.id}"}
                      class={[
                        "flex min-h-11 w-full flex-col items-center justify-center gap-1.5 rounded-[14px] border border-dashed border-strong text-sm text-muted hover:bg-base-200",
                        slot.entries == [] && "flex-1"
                      ]}
                    >
                      <.icon name="hero-plus" class="size-5" />Add
                    </button>
                  </div>
                </div>
              </div>
            </div>
            <p class="mt-3 text-xs text-muted">
              Select an Add slot, then choose a recipe. Scroll sideways to see the full week.
            </p>
          </section>
          <aside
            id="recipe-tray"
            class="surface w-full space-y-3.5 p-[18px] xl:w-[280px] xl:shrink-0"
            aria-label="Add recipes"
          >
            <h2 class="text-lg">Add from your recipes</h2>
            <.form
              for={@slot_form}
              as={:slot}
              id="tray-slot"
              phx-change="select_slot"
              class="grid grid-cols-2 gap-2"
            >
              <.input
                name="slot[day]"
                type="select"
                value={@selected_day}
                aria-label="Day to add recipe"
                options={for day <- 1..7, do: {Planner.short_day_name(day), day}}
                class="field !px-2 !text-sm"
              /><.input
                name="slot[meal]"
                type="select"
                value={@selected_meal}
                aria-label="Meal to add recipe"
                options={[{"Lunch", "lunch"}, {"Dinner", "dinner"}]}
                class="field !px-2 !text-sm"
              />
            </.form>
            <.form
              for={@search_form}
              id="tray-search-form"
              phx-change="search_recipes"
              phx-submit="search_recipes"
            >
              <.input
                field={@search_form[:search]}
                id="tray-search"
                type="search"
                placeholder="Search recipes"
                aria-label="Search recipes"
                phx-debounce="200"
                class="field !border-base-300 !bg-base-100"
              />
            </.form>
            <button
              id="tray-quick"
              phx-click="quick"
              aria-pressed={to_string(@quick)}
              class={[
                "min-h-11 rounded-full px-3 text-xs font-bold",
                if(@quick, do: "bg-base-content text-base-100", else: "bg-tag text-secondary-ink")
              ]}
            >
              Under 30 min
            </button>
            <p :if={@tray_empty?} class="text-sm text-muted">
              No matching recipes.
              <.link navigate="/recipes/new" class="inline-flex min-h-11 items-center underline">
                Create one
              </.link>
            </p>
            <div id="tray-recipes" phx-update="stream" class="space-y-1">
              <div
                :for={{id, recipe} <- @streams.tray}
                id={id}
                class="flex items-center gap-3 rounded-xl py-2"
              >
                <span class={[
                  "flex size-10 shrink-0 items-center justify-center rounded-xl",
                  tone(recipe.id)
                ]}>
                  <.icon name="hero-book-open" class="size-5" />
                </span>
                <span class="min-w-0 flex-1"><span class="block text-sm font-bold">{recipe.title}</span><span
                  :if={recipe.total_time_minutes}
                  class="text-xs text-muted"
                >{recipe.total_time_minutes} min</span></span><button
                  id={"tray-add-#{recipe.id}"}
                  phx-click="assign_recipe"
                  phx-value-recipe-id={recipe.id}
                  aria-label={"Add #{recipe.title} to the plan"}
                  class="action size-11 shrink-0 !p-0"
                ><.icon name="hero-plus" class="size-4" /></button>
              </div>
            </div>
          </aside>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp plan_lunch_count(plan),
    do:
      plan.entries
      |> Enum.filter(&(&1.meal_type == :lunch))
      |> Enum.uniq_by(& &1.day_of_week)
      |> length()
end

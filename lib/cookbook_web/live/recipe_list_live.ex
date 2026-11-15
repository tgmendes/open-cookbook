defmodule CookbookWeb.RecipeListLive do
  use CookbookWeb, :live_view
  alias Cookbook.{Recipes, Planner}

  def mount(_params, _session, socket) do
    socket = stream_configure(socket, :recipes, dom_id: fn card -> "recipe-#{card.id}" end)

    {:ok,
     assign(socket,
       tags: Recipes.list_tags(socket.assigns.current_user.id),
       search: "",
       selected_tag: nil,
       sort: "recent",
       planning_recipe: nil,
       page_title: "Recipes",
       search_form: to_form(%{"search" => ""}),
       slot_form:
         to_form(%{"date" => Date.to_iso8601(Date.utc_today()), "meal_type" => "dinner"},
           as: :slot
         )
     ), layout: false}
  end

  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(
       search: params["search"] || "",
       selected_tag: if(params["tag"] in [nil, ""], do: nil, else: params["tag"]),
       sort: params["sort"] || "recent"
     )
     |> refresh()}
  end

  def handle_event("search", %{"search" => search}, socket),
    do: patch_filters(socket, %{search: search})

  def handle_event("filter_tag", %{"tag" => tag}, socket), do: patch_filters(socket, %{tag: tag})
  def handle_event("sort", %{"sort" => sort}, socket), do: patch_filters(socket, %{sort: sort})
  def handle_event("close-plan", _, socket), do: {:noreply, assign(socket, planning_recipe: nil)}

  def handle_event("add_to_plan", %{"id" => id}, socket) do
    recipe = Recipes.get_recipe!(id)

    if recipe.user_id == socket.assigns.current_user.id,
      do: {:noreply, assign(socket, planning_recipe: recipe)},
      else: {:noreply, socket}
  end

  def handle_event("save-plan", %{"slot" => %{"date" => date, "meal_type" => type}}, socket) do
    with recipe when not is_nil(recipe) <- socket.assigns.planning_recipe,
         {:ok, date} <- Date.from_iso8601(date),
         true <- type in ["lunch", "dinner"],
         {:ok, plan} <- Planner.get_or_create_plan_for_week(socket.assigns.current_user.id, date),
         {:ok, _} <-
           Planner.add_entry(plan, %{
             recipe_id: recipe.id,
             day_of_week: Date.day_of_week(date),
             meal_type: if(type == "lunch", do: :lunch, else: :dinner)
           }) do
      {:noreply,
       socket
       |> assign(planning_recipe: nil)
       |> put_flash(:info, "Added to your meal plan.")
       |> refresh()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Choose a valid date and meal.")}
    end
  end

  defp patch_filters(socket, changes) do
    params =
      Map.merge(
        %{
          search: socket.assigns.search,
          tag: socket.assigns.selected_tag || "",
          sort: socket.assigns.sort
        },
        changes
      )

    {:noreply, push_patch(socket, to: ~p"/recipes?#{params}")}
  end

  defp refresh(socket) do
    recipes =
      Recipes.list_recipes(socket.assigns.current_user.id,
        search: socket.assigns.search,
        tag: socket.assigns.selected_tag
      )

    recipes =
      case socket.assigns.sort do
        "title" -> Enum.sort_by(recipes, &String.downcase(&1.title))
        "time" -> Enum.sort_by(recipes, &(&1.total_time_minutes || 100_000))
        _ -> recipes
      end

    {:ok, plan} =
      Planner.get_or_create_plan_for_week(socket.assigns.current_user.id, Date.utc_today())

    planned = plan.entries |> Enum.sort_by(& &1.day_of_week) |> Enum.group_by(& &1.recipe_id)

    cards =
      Enum.map(recipes, fn recipe ->
        entry = planned |> Map.get(recipe.id, []) |> List.first()

        %{
          id: recipe.id,
          recipe: recipe,
          planned: entry && Planner.short_day_name(entry.day_of_week)
        }
      end)

    socket
    |> assign(
      recipe_count: length(recipes),
      navigation: Planner.navigation_summary(socket.assigns.current_user.id),
      search_form: to_form(%{"search" => socket.assigns.search})
    )
    |> stream(:recipes, cards, reset: true)
  end

  defp tone(id),
    do:
      Enum.at(
        [
          "bg-peach text-peach-ink",
          "bg-blush text-blush-ink",
          "bg-butter text-butter-ink",
          "bg-sage text-sage-ink",
          "bg-lavender text-lavender-ink",
          "bg-sky text-sky-ink"
        ],
        :erlang.phash2(id, 6)
      )

  def render(assigns) do
    assigns = assign(assigns, :sort_form, to_form(%{"sort" => assigns.sort}))

    ~H"""
    <Layouts.app {assigns}>
      <div class="space-y-7">
        <header class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 class="text-4xl">Recipes</h1>
            <p class="mt-1.5 text-[15px] text-muted">Your collection, ready to plan or cook.</p>
          </div>
          <div class="flex flex-wrap gap-2.5">
            <.link navigate={~p"/recipes/new?mode=url"} class="action">
              <.icon name="hero-link" class="size-4" />Import from link
            </.link>
            <.link navigate={~p"/recipes/new?mode=generate"} class="action">
              <.icon
                name="hero-sparkles"
                class="size-4"
              />Describe it
            </.link><.link navigate={~p"/recipes/new"} class="action action-primary"><.icon
              name="hero-plus"
              class="size-4"
            />New recipe</.link>
          </div>
        </header>
        <section aria-label="Find a recipe" class="space-y-3.5">
          <.form
            for={@search_form}
            id="recipe-search"
            phx-change="search"
            phx-submit="search"
            class="relative"
          >
            <span class="pointer-events-none absolute top-4 left-4 text-muted">
              <.icon name="hero-magnifying-glass" class="size-5" />
            </span>
            <.input
              field={@search_form[:search]}
              type="search"
              aria-label="Search recipes"
              placeholder="Search by dish, ingredient or tag"
              phx-debounce="300"
              class="field min-h-14 !rounded-2xl !border-base-300 !pl-12"
            />
          </.form>
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div id="recipe-filters" class="flex flex-wrap gap-2">
              <button
                :for={tag <- ["" | @tags]}
                phx-click="filter_tag"
                phx-value-tag={tag}
                aria-pressed={to_string((@selected_tag || "") == tag)}
                class={[
                  "min-h-11 rounded-full border px-4 text-sm font-bold transition-colors",
                  if((@selected_tag || "") == tag,
                    do: "border-base-content bg-base-content text-base-100",
                    else: "border-base-300 bg-base-200 hover:border-strong"
                  )
                ]}
              >
                {if tag == "", do: "All", else: tag}
              </button>
            </div>
            <.form for={@sort_form} id="recipe-sort" phx-change="sort">
              <.input
                type="select"
                name="sort"
                value={@sort}
                aria-label="Sort recipes"
                options={[
                  {"Recently updated", "recent"},
                  {"Name", "title"},
                  {"Quickest first", "time"}
                ]}
                class="field !w-auto !border-0 !bg-transparent !text-sm"
              />
            </.form>
          </div>
        </section>
        <section
          :if={@navigation.tonight}
          id="tonight-banner"
          class="flex flex-wrap items-center gap-5 rounded-[20px] border border-transparent bg-teal-tint p-5 dark:border-base-300 dark:bg-base-200"
          aria-label="Tonight"
        >
          <div class="flex size-[72px] shrink-0 items-center justify-center rounded-[18px] bg-peach">
            <.icon name="hero-cake" class="size-9 text-peach-ink" />
          </div>
          <div class="min-w-0 flex-1 basis-56">
            <p class="eyebrow !text-muted">On the plan tonight</p>
            <h2 class="mt-1 text-[22px]">{@navigation.tonight.title}</h2>
            <p class="mt-1 text-sm text-muted">
              <span :if={@navigation.tonight.total_time_minutes}>
                {@navigation.tonight.total_time_minutes} min ·
              </span>
              <span :if={@navigation.tonight.servings}>serves {@navigation.tonight.servings} · </span>Ingredients are on your shopping list
            </p>
          </div>
          <div class="flex flex-wrap gap-2.5">
            <.link navigate="/planner" class="action">Swap meal</.link><.link
              navigate={~p"/recipes/#{@navigation.tonight.id}/cook"}
              class="action action-primary"
            >Start cooking <.icon name="hero-arrow-right" class="size-4" /></.link>
          </div>
        </section>
        <section aria-label="All recipes" class="space-y-3.5">
          <div class="flex items-baseline justify-between">
            <h2 class="text-xl">{@selected_tag || "All recipes"}</h2>
            <span class="text-sm text-muted">
              {@recipe_count} {if @recipe_count == 1, do: "recipe", else: "recipes"}
            </span>
          </div>
          <div :if={@recipe_count == 0} id="recipes-empty" class="surface space-y-3 p-10 text-center">
            <h3 class="text-xl">
              {if @search != "" || @selected_tag,
                do: "No matching recipes",
                else: "Your collection starts here"}
            </h3>
            <p class="text-muted">Try another search, or add something you'd love to cook.</p>
            <.link navigate="/recipes/new" class="action action-primary">New recipe</.link>
          </div>
          <div
            id="recipe-grid"
            phx-update="stream"
            class="grid grid-cols-[repeat(auto-fill,minmax(232px,1fr))] gap-[18px]"
          >
            <article
              :for={{id, card} <- @streams.recipes}
              id={id}
              class="surface group flex flex-col overflow-hidden transition-shadow hover:shadow-md"
            >
              <div class={[
                "relative flex h-[150px] items-center justify-center overflow-hidden",
                tone(card.id)
              ]}>
                <img
                  :if={card.recipe.image_url}
                  src={card.recipe.image_url}
                  alt=""
                  loading="lazy"
                  class="size-full object-cover transition-transform duration-300 group-hover:scale-105"
                />
                <div
                  :if={!card.recipe.image_url}
                  class="flex size-24 items-center justify-center rounded-full border-[12px] border-base-100 bg-base-200 shadow-sm"
                >
                  <.icon name="hero-cake" class="size-9" />
                </div>
                <span
                  :if={card.recipe.total_time_minutes}
                  class="absolute top-3 left-3 flex items-center gap-1 rounded-full bg-base-200 px-2.5 py-1 text-xs font-bold text-base-content"
                >
                  <.icon name="hero-clock" class="size-3.5" />{card.recipe.total_time_minutes} min
                </span>
                <span
                  :if={card.planned}
                  data-planned
                  class="absolute top-3 right-3 rounded-full bg-primary px-2.5 py-1 text-xs font-bold text-primary-content"
                >
                  Planned · {card.planned}
                </span>
              </div>
              <div class="flex flex-1 flex-col gap-2.5 px-4 pt-3.5 pb-4">
                <h3 class="text-[17px] leading-snug">
                  <.link
                    navigate={~p"/recipes/#{card.id}"}
                    class="inline-flex min-h-11 items-center hover:underline"
                  >
                    {card.recipe.title}
                  </.link>
                </h3>
                <p :if={card.recipe.servings} class="text-[13px] text-muted">
                  Serves {card.recipe.servings}
                </p>
                <div class="flex flex-wrap gap-1.5">
                  <span
                    :for={tag <- card.recipe.tags}
                    class="rounded-full bg-tag px-2.5 py-1 text-xs text-secondary-ink"
                  >
                    {tag}
                  </span>
                </div>
                <div class="mt-auto flex gap-2 pt-1">
                  <button
                    id={"plan-recipe-#{card.id}"}
                    phx-click="add_to_plan"
                    phx-value-id={card.id}
                    class="action min-w-0 flex-1 !px-2 !text-[13px]"
                  >
                    <.icon name="hero-calendar-days" class="size-4" />{if card.planned,
                      do: "Planned · #{card.planned}",
                      else: "Add to plan"}
                  </button>
                  <.link
                    navigate={~p"/recipes/#{card.id}/cook"}
                    aria-label={"Cook #{card.recipe.title}"}
                    class="flex size-11 items-center justify-center rounded-xl bg-teal-tint text-teal-ink"
                  >
                    <.icon name="hero-fire" class="size-5" />
                  </.link>
                </div>
              </div>
            </article>
          </div>
        </section>
      </div>
      <div
        :if={@planning_recipe}
        id="plan-recipe-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="plan-dialog-title"
        class="fixed inset-0 z-50 flex items-center justify-center p-5"
      >
        <div class="absolute inset-0 bg-black/50" phx-click="close-plan"></div>
        <section
          class="surface relative w-full max-w-md space-y-5 p-6"
          phx-window-keydown="close-plan"
          phx-key="Escape"
        >
          <div class="flex items-center justify-between">
            <h2 id="plan-dialog-title" class="text-xl">Add to your plan</h2>
            <button class="action size-11 !p-0" phx-click="close-plan" aria-label="Close">
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>
          <p class="text-muted">{@planning_recipe.title}</p>
          <.form for={@slot_form} id="add-to-plan-form" phx-submit="save-plan" class="space-y-3">
            <.input field={@slot_form[:date]} type="date" label="Day" class="field" required /><.input
              field={@slot_form[:meal_type]}
              type="select"
              label="Meal"
              options={[{"Lunch", "lunch"}, {"Dinner", "dinner"}]}
              class="field"
            /><button class="action action-primary w-full" type="submit">Add to plan</button>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end
end

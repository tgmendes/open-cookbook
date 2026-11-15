defmodule CookbookWeb.CookModeLive do
  use CookbookWeb, :live_view
  alias Cookbook.{AI, Recipes}
  alias Cookbook.Recipes.Step

  def mount(%{"id" => id}, _session, socket) do
    recipe = Recipes.get_recipe!(id)

    cond do
      recipe.user_id != socket.assigns.current_user.id ->
        {:ok, push_navigate(socket, to: ~p"/recipes")}

      recipe.steps == [] ->
        {:ok,
         socket
         |> put_flash(:error, "This recipe has no steps to cook.")
         |> push_navigate(to: ~p"/recipes/#{recipe.id}")}

      true ->
        {:ok,
         assign(socket,
           recipe: recipe,
           steps: Enum.sort_by(recipe.steps, & &1.position),
           current_step: -1,
           gathered: MapSet.new(),
           show_ingredients: false,
           adjusted_ingredients: nil,
           adjusted_servings: nil,
           requested_servings: recipe.servings || 2,
           adjust_loading: false,
           adjust_error: nil,
           page_title: "Cook: #{recipe.title}"
         ), layout: false}
    end
  end

  def handle_event("start", _, socket), do: {:noreply, assign(socket, current_step: 0)}
  def handle_event("next", _, socket), do: {:noreply, move(socket, 1)}
  def handle_event("prev", _, socket), do: {:noreply, move(socket, -1)}
  def handle_event("keydown", %{"key" => "ArrowRight"}, socket), do: {:noreply, move(socket, 1)}
  def handle_event("keydown", %{"key" => "ArrowLeft"}, socket), do: {:noreply, move(socket, -1)}

  def handle_event("keydown", %{"key" => "Escape"}, socket),
    do: {:noreply, assign(socket, current_step: -1)}

  def handle_event("keydown", _, socket), do: {:noreply, socket}

  def handle_event("toggle-ingredients", _, socket),
    do: {:noreply, assign(socket, show_ingredients: !socket.assigns.show_ingredients)}

  def handle_event("go-to-step", %{"step" => value}, socket) do
    case Integer.parse(value) do
      {index, ""} when index >= 0 ->
        {:noreply, assign(socket, current_step: min(index, length(socket.assigns.steps) - 1))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("gather", %{"index" => index}, socket) do
    gathered = socket.assigns.gathered

    gathered =
      if MapSet.member?(gathered, index),
        do: MapSet.delete(gathered, index),
        else: MapSet.put(gathered, index)

    {:noreply, assign(socket, gathered: gathered)}
  end

  def handle_event("servings", %{"direction" => direction}, socket) do
    if socket.assigns.adjust_loading do
      {:noreply, socket}
    else
      delta = if direction == "more", do: 1, else: -1
      servings = (socket.assigns.requested_servings + delta) |> max(1) |> min(12)
      recipe = socket.assigns.recipe
      unit_system = socket.assigns.current_user.unit_system

      {:noreply,
       socket
       |> assign(requested_servings: servings, adjust_loading: true, adjust_error: nil)
       |> start_async(:adjust_quantities, fn ->
         AI.adjust_quantities(recipe, servings, unit_system)
       end)}
    end
  end

  def handle_async(
        :adjust_quantities,
        {:ok, {:ok, %{ingredients: ingredients, servings: servings}}},
        socket
      ) do
    {:noreply,
     assign(socket,
       adjusted_ingredients: ingredients,
       adjusted_servings: servings,
       requested_servings: servings,
       adjust_loading: false,
       gathered: MapSet.new()
     )}
  end

  def handle_async(:adjust_quantities, _, socket) do
    {:noreply,
     assign(socket,
       adjust_loading: false,
       requested_servings:
         socket.assigns.adjusted_servings || socket.assigns.recipe.servings || 2,
       adjust_error: "Couldn't adjust quantities. Your original amounts are unchanged. Try again."
     )}
  end

  defp move(socket, delta),
    do:
      assign(socket,
        current_step:
          max(-1, min(socket.assigns.current_step + delta, length(socket.assigns.steps)))
      )

  @modifiers ~w(plain fresh dried whole ground fine extra large small medium chopped sliced diced minced grated crushed peeled canned frozen)
  defp matched_ingredients(step, ingredients) do
    Enum.filter(ingredients, fn ing ->
      words =
        ing.name
        |> String.split()
        |> Enum.reject(&(String.length(&1) < 4 || String.downcase(&1) in @modifiers))

      Regex.match?(~r/\b#{Regex.escape(ing.name)}\b/i, step.instruction) ||
        Enum.any?(words, &Regex.match?(~r/\b#{Regex.escape(&1)}\b/i, step.instruction))
    end)
  end

  defp lane_class(index),
    do: Enum.at(["bg-lavender", "bg-butter", "bg-peach", "bg-sage", "bg-sky"], rem(index, 5))

  defp equipment(steps) do
    text = Enum.map_join(steps, " ", & &1.instruction)

    [
      "Chopping board",
      "Knife",
      "Baking tray",
      "Saucepan",
      "Frying pan",
      "Wok",
      "Grater",
      "Mixing bowl",
      "Colander",
      "Sieve"
    ]
    |> Enum.filter(&Regex.match?(~r/\b#{Regex.escape(&1)}\b/i, text))
  end

  def render(assigns) do
    ingredients = assigns.adjusted_ingredients || assigns.recipe.ingredients
    step = Enum.at(assigns.steps, max(assigns.current_step, 0))
    next_step = Enum.at(assigns.steps, assigns.current_step + 1)

    assigns =
      assign(assigns,
        ingredients: ingredients,
        equipment: equipment(assigns.steps),
        step: step,
        next_step: next_step,
        step_ingredients: if(step, do: matched_ingredients(step, ingredients), else: []),
        total_minutes:
          (assigns.recipe.prep_time_minutes || 0) + (assigns.recipe.cook_time_minutes || 0),
        timeline_minutes: max(Enum.sum(Enum.map(assigns.steps, &(&1.duration_minutes || 1))), 1)
      )

    ~H"""
    <Layouts.app {assigns} immersive>
      <div
        id="cook-mode"
        phx-hook="ScreenWakeLock"
        phx-window-keydown="keydown"
        class="min-h-dvh bg-base-100"
      >
        <section :if={@current_step == -1} id="cook-prep" class="mx-auto max-w-3xl pb-32">
          <div class="relative flex h-44 items-center justify-center overflow-hidden bg-peach sm:h-60">
            <img
              :if={@recipe.image_url}
              src={@recipe.image_url}
              alt=""
              class="size-full object-cover"
            />
            <div
              :if={!@recipe.image_url}
              class="flex size-28 items-center justify-center rounded-full border-[14px] border-base-100 bg-base-200 shadow-sm"
            >
              <.icon name="hero-cake" class="size-10 text-peach-ink" />
            </div>
            <.link
              navigate={~p"/recipes/#{@recipe.id}"}
              aria-label="Close cook mode"
              class="action absolute top-4 left-4 size-11 !rounded-full !p-0"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </.link>
          </div>
          <div class="space-y-6 p-5 sm:p-8">
            <header class="space-y-1.5">
              <p class="eyebrow">Before you start</p>
              <h1 class="text-[26px] leading-tight sm:text-4xl">{@recipe.title}</h1>
              <p class="text-sm text-muted">
                <span :if={@total_minutes > 0}>{@total_minutes} min total · </span>{length(@steps)} steps
              </p>
            </header>
            <div class="surface flex items-center justify-between gap-3 !rounded-2xl p-2.5 pl-4">
              <span class="font-bold">Servings</span>
              <div class="flex items-center gap-2">
                <button
                  id="fewer-servings"
                  aria-label="Fewer servings"
                  phx-click="servings"
                  phx-value-direction="less"
                  disabled={@adjust_loading || @requested_servings <= 1}
                  class="action size-11 !p-0"
                >
                  <.icon name="hero-minus" class="size-5" />
                </button>
                <span
                  id="servings"
                  aria-live="polite"
                  class="min-w-9 text-center font-heading text-xl font-semibold"
                >
                  {@requested_servings}
                </span>
                <button
                  id="more-servings"
                  aria-label="More servings"
                  phx-click="servings"
                  phx-value-direction="more"
                  disabled={@adjust_loading || @requested_servings >= 12}
                  class="action size-11 !p-0"
                >
                  <.icon name="hero-plus" class="size-5" />
                </button>
              </div>
            </div>
            <p :if={@adjust_loading} role="status" class="text-sm text-muted">
              Adjusting quantities…
            </p>
            <p
              :if={@adjust_error}
              id="adjust-error"
              role="alert"
              class="rounded-xl bg-blush p-3 text-sm text-blush-ink"
            >
              {@adjust_error}
            </p>
            <section aria-label="How it comes together" class="space-y-3">
              <h2 class="text-lg">How it comes together</h2>
              <div class="surface space-y-3 p-4">
                <div :for={{s, i} <- Enum.with_index(@steps)} class="space-y-1">
                  <p class="text-xs text-secondary-ink">
                    {Step.title(s)} <span :if={s.duration_minutes}>· {s.duration_minutes} min</span>
                  </p>
                  <div class="h-3 overflow-hidden rounded-full bg-tag">
                    <div
                      class={["h-full rounded-full", lane_class(i)]}
                      style={"width: #{max(5, (s.duration_minutes || 1) / @timeline_minutes * 100)}%"}
                    >
                    </div>
                  </div>
                </div>
                <p class="text-xs text-muted">A quick overview of the steps, in recipe order.</p>
              </div>
            </section>
            <section aria-label="Gather ingredients" class="space-y-3">
              <div class="flex items-baseline justify-between">
                <h2 class="text-lg">Gather</h2>
                <span class="text-sm text-muted">
                  {MapSet.size(@gathered)} of {length(@ingredients)} ready
                </span>
              </div>
              <div class="surface divide-y divide-base-300 overflow-hidden">
                <button
                  :for={{ing, i} <- Enum.with_index(@ingredients)}
                  id={"gather-#{i}"}
                  role="checkbox"
                  aria-checked={to_string(MapSet.member?(@gathered, to_string(i)))}
                  phx-click="gather"
                  phx-value-index={i}
                  class="flex min-h-[52px] w-full items-center gap-3 px-3.5 py-2 text-left hover:bg-tag"
                >
                  <span class={[
                    "flex size-6 shrink-0 items-center justify-center rounded-lg border-2",
                    if(MapSet.member?(@gathered, to_string(i)),
                      do: "border-primary bg-primary text-primary-content",
                      else: "border-checkbox"
                    )
                  ]}>
                    <.icon
                      :if={MapSet.member?(@gathered, to_string(i))}
                      name="hero-check"
                      class="size-4"
                    />
                  </span>
                  <span class="min-w-16 font-bold">{ing.quantity} {ing.unit}</span><span class={[
                    MapSet.member?(@gathered, to_string(i)) && "text-muted"
                  ]}>{ing.name}</span>
                </button>
              </div>
            </section>
            <section
              :if={@equipment != []}
              id="cook-equipment"
              aria-label="Equipment"
              class="space-y-3"
            >
              <h2 class="text-lg">Equipment</h2>
              <div class="flex flex-wrap gap-2">
                <span
                  :for={item <- @equipment}
                  class="rounded-full bg-sky px-3 py-2 text-sm text-sky-ink"
                >
                  {item}
                </span>
              </div>
            </section>
          </div>
          <footer class="fixed inset-x-0 bottom-0 z-10 border-t border-base-300 bg-base-200 px-5 py-4 pb-[max(20px,env(safe-area-inset-bottom))]">
            <div class="mx-auto max-w-2xl space-y-2">
              <button
                id="start-cooking"
                phx-click="start"
                class="action action-primary min-h-14 w-full !text-base"
              >
                Start cooking <.icon name="hero-arrow-right" class="size-5" />
              </button>
              <p class="text-center text-xs text-muted">Your screen stays on while you cook.</p>
            </div>
          </footer>
        </section>

        <header
          :if={@current_step >= 0}
          class="flex flex-wrap items-center gap-3 border-b border-base-300 bg-base-200 px-5 py-4 lg:gap-5 lg:px-7"
        >
          <.link
            navigate={~p"/recipes/#{@recipe.id}"}
            aria-label="Exit cook mode"
            class="action size-12 !p-0"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </.link>
          <div class="min-w-0 flex-1">
            <h1 class="truncate text-base lg:text-lg">{@recipe.title}</h1>
            <p class="text-sm text-muted">
              {min(@current_step + 1, length(@steps))} of {length(@steps)} steps · {@adjusted_servings ||
                @recipe.servings || 2} servings
            </p>
          </div>
          <button id="all-ingredients" phx-click="toggle-ingredients" class="action !px-3">
            <.icon name="hero-list-bullet" class="size-5" />
            <span class="hidden sm:inline">
              All ingredients
            </span>
          </button>
          <nav aria-label="Steps" class="flex w-full gap-1.5 lg:order-none lg:w-auto lg:flex-1">
            <button
              :for={{s, i} <- Enum.with_index(@steps)}
              id={"step-nav-#{i}"}
              phx-click="go-to-step"
              phx-value-step={i}
              aria-label={"Step #{i + 1}: #{Step.title(s)}"}
              aria-current={@current_step == i && "step"}
              class="flex min-h-11 flex-1 items-center"
            >
              <span class={[
                "h-2 w-full rounded-full",
                if(i <= @current_step, do: "bg-primary", else: "bg-base-300")
              ]}>
              </span>
            </button>
          </nav>
        </header>
        <div class={[
          @current_step >= 0 &&
            "mx-auto flex max-w-[1400px] flex-col lg:min-h-[calc(100dvh-100px)] lg:flex-row"
        ]}>
          <section
            :if={@current_step >= 0 && @step}
            id="cook-step"
            data-step={@current_step}
            class="flex min-w-0 flex-1 flex-col gap-7 px-5 py-8 lg:px-14 lg:py-11"
          >
            <h2 id="step-heading" class="eyebrow">Step {@current_step + 1} · {Step.title(@step)}</h2>
            <p
              aria-live="polite"
              class="max-w-3xl font-heading text-[28px] leading-[1.32] font-medium lg:text-[38px]"
            >
              {@step.instruction}
            </p>
            <section :if={@step_ingredients != []} aria-label="For this step" class="space-y-2.5">
              <h3 class="eyebrow">For this step</h3>
              <div class="flex flex-wrap gap-2.5">
                <span
                  :for={ing <- @step_ingredients}
                  class="surface inline-flex items-baseline gap-2 !rounded-[14px] px-4 py-3 text-lg"
                >
                  <strong>{ing.quantity} {ing.unit}</strong><span>{ing.name}</span>
                </span>
              </div>
            </section>
            <button
              :if={@step.duration_minutes && @step.duration_minutes > 0}
              id="start-timer"
              class="action action-primary min-h-15 self-start !text-lg"
              phx-click={
                JS.dispatch("cook:start-timer",
                  detail: %{
                    id: @step.id,
                    label: Step.title(@step),
                    seconds: @step.duration_minutes * 60
                  }
                )
              }
            >
              <.icon name="hero-clock" class="size-6" />Start {@step.duration_minutes}-min timer
            </button>
            <div class="mt-auto flex gap-3 pt-8">
              <button id="previous-step" phx-click="prev" class="action min-h-16 !px-4 sm:min-w-36">
                <.icon name="hero-chevron-left" class="size-5" />Back
              </button>
              <button
                id="next-step"
                phx-click="next"
                class="action action-primary min-h-16 min-w-0 flex-1 justify-between text-left"
              ><span class="min-w-0"><span class="block text-xs">{if @next_step, do: "NEXT · STEP #{@current_step + 2}", else: "ALL DONE"}</span><span class="block truncate">{if @next_step, do: Step.title(@next_step), else: "Finish cooking"}</span></span><.icon
                name="hero-arrow-right"
                class="size-6 shrink-0"
              /></button>
            </div>
            <p class="text-xs text-muted">Tip: use ← and → on a keyboard.</p>
          </section>
          <section
            :if={@current_step == length(@steps)}
            id="cook-finished"
            class="flex-1 space-y-5 p-8 text-center lg:p-20"
          >
            <.icon name="hero-check-circle" class="size-16 text-primary" />
            <h2 class="text-3xl">Enjoy your meal.</h2>
            <p class="text-muted">
              That's everything. Your timers stay here until you leave cook mode.
            </p>
            <.link navigate={~p"/recipes/#{@recipe.id}"} class="action action-primary">
              Back to recipe
            </.link>
          </section>
          <aside
            class={[
              @current_step == -1 && "hidden",
              "space-y-4 border-t border-base-300 p-5 lg:w-80 lg:shrink-0 lg:border-t-0 lg:border-l lg:p-6"
            ]}
            aria-label="Timers"
          >
            <h2 class="text-lg">Timers</h2>
            <div id="cook-timers" phx-hook="CookTimers" phx-update="ignore" class="space-y-3">
              <p class="text-sm text-muted">
                Timers you start show up here and keep running as you move between steps.
              </p>
            </div>
            <div :if={@next_step && @current_step >= 0} class="rounded-2xl bg-sage p-4 text-sage-ink">
              <h3 class="eyebrow !text-inherit">Coming up</h3>
              <p class="mt-2 text-sm leading-relaxed">{@next_step.instruction}</p>
            </div>
          </aside>
        </div>
        <div
          :if={@show_ingredients}
          id="ingredients-drawer"
          role="dialog"
          aria-modal="true"
          aria-label="All ingredients"
          class="fixed inset-0 z-50"
        >
          <div class="absolute inset-0 bg-black/50" phx-click="toggle-ingredients"></div>
          <section
            class="absolute inset-y-0 right-0 w-80 max-w-[90vw] overflow-y-auto border-l border-base-300 bg-base-200 p-5"
            phx-window-keydown="toggle-ingredients"
            phx-key="Escape"
          >
            <div class="mb-5 flex items-center justify-between">
              <h2 class="text-xl">All ingredients</h2>
              <button
                phx-click="toggle-ingredients"
                aria-label="Close ingredients"
                class="action size-11 !p-0"
              >
                <.icon name="hero-x-mark" class="size-5" />
              </button>
            </div>
            <ul class="divide-y divide-base-300">
              <li :for={ing <- @ingredients} class="py-3">
                <strong>{ing.quantity} {ing.unit}</strong> {ing.name}
              </li>
            </ul>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

defmodule CookbookWeb.ShoppingListLive do
  use CookbookWeb, :live_view
  alias Cookbook.Planner
  alias Cookbook.Planner.ShoppingSections

  def mount(params, _session, socket) do
    week_start = Planner.week_from_param(params["week"])
    {:ok, plan} = Planner.get_or_create_plan_for_week(socket.assigns.current_user.id, week_start)

    {:ok,
     socket
     |> assign(
       plan: plan,
       week_start: week_start,
       grouping: "aisle",
       page_title: "Shopping list",
       extra_form: to_form(%{"name" => ""}, as: :extra)
     )
     |> refresh(), layout: false}
  end

  def handle_event("toggle_item", %{"id" => id}, socket) do
    if Enum.any?(Planner.shopping_items(socket.assigns.plan), &(&1.id == id)) do
      checked = socket.assigns.plan.shopping_checked
      checked = if id in checked, do: List.delete(checked, id), else: [id | checked]
      save(socket, %{shopping_checked: checked})
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_extra", %{"extra" => %{"name" => name}}, socket) do
    name = String.trim(name)
    extras = socket.assigns.plan.shopping_extras

    if name != "" && String.length(name) <= 150 && length(extras) < 200 do
      save(socket, %{shopping_extras: Enum.uniq(extras ++ [name])})
    else
      {:noreply,
       put_flash(socket, :error, "Enter an item up to 150 characters (maximum 200 extras).")}
    end
  end

  def handle_event("group", %{"by" => by}, socket) when by in ["aisle", "recipe"] do
    {:noreply, socket |> assign(grouping: by) |> refresh()}
  end

  defp save(socket, attrs) do
    case Planner.update_shopping_state(socket.assigns.plan, attrs) do
      {:ok, plan} ->
        {:noreply,
         socket
         |> assign(plan: plan, extra_form: to_form(%{"name" => ""}, as: :extra))
         |> refresh()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't save your shopping list. Try again.")}
    end
  end

  defp refresh(socket) do
    plan = socket.assigns.plan
    items = Planner.shopping_items(plan)
    {basket, remaining} = Enum.split_with(items, &(&1.id in plan.shopping_checked))

    groups =
      if socket.assigns.grouping == "aisle" do
        grouped = Enum.group_by(remaining, &ShoppingSections.section(&1.name))

        for section <- ShoppingSections.order(),
            list = Map.get(grouped, section, []),
            list != [],
            do: %{id: section, name: section, items: list, tone: ShoppingSections.tone(section)}
      else
        remaining
        |> Enum.flat_map(fn item ->
          Enum.map(if(item.recipes == [], do: ["Extra items"], else: item.recipes), &{&1, item})
        end)
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {name, list} ->
          %{id: name, name: name, items: list, tone: "bg-sky text-sky-ink"}
        end)
      end

    navigation = Planner.navigation_summary(socket.assigns.current_user.id)

    socket
    |> assign(
      total_count: length(items),
      basket_count: length(basket),
      remaining_count: length(remaining),
      navigation: navigation,
      empty?: items == []
    )
    |> stream(:groups, groups, reset: true)
    |> stream(:basket, basket, reset: true)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app {assigns}>
      <div class="mx-auto max-w-xl space-y-5">
        <header class="space-y-4">
          <div class="flex items-center justify-between">
            <.link
              navigate={~p"/planner?week=#{Date.to_iso8601(@week_start)}"}
              aria-label="Back to meal plan"
              class="flex size-11 items-center justify-center rounded-xl hover:bg-base-200"
            >
              <.icon name="hero-chevron-left" class="size-6" />
            </.link>
            <span class="text-sm text-muted">
              {Calendar.strftime(@week_start, "%b %-d")} – {Calendar.strftime(
                Date.add(@week_start, 6),
                "%b %-d"
              )}
            </span>
          </div>
          <div>
            <h1 class="text-3xl sm:text-4xl">Shopping list</h1>
            <p class="mt-1 text-sm text-muted">
              For your week · {length(@plan.entries)} {if length(@plan.entries) == 1,
                do: "meal",
                else: "meals"}
            </p>
          </div>
          <div class="flex items-center gap-3">
            <progress
              id="shopping-progress"
              class="h-2 flex-1 overflow-hidden rounded-full [&::-webkit-progress-bar]:bg-base-300 [&::-webkit-progress-value]:bg-primary [&::-moz-progress-bar]:bg-primary"
              max={max(@total_count, 1)}
              value={@basket_count}
              aria-label="Shopping progress"
            >
            </progress><span class="text-sm font-bold tabular-nums">{@basket_count}/{@total_count}</span>
          </div>
          <div role="tablist" aria-label="Group by" class="flex rounded-xl bg-base-300/50 p-1">
            <button
              id="group-by-aisle"
              role="tab"
              aria-selected={to_string(@grouping == "aisle")}
              phx-click="group"
              phx-value-by="aisle"
              class={[
                "min-h-11 flex-1 rounded-lg text-sm font-bold",
                @grouping == "aisle" && "bg-base-200 shadow-sm"
              ]}
            >
              By aisle
            </button>
            <button
              id="group-by-recipe"
              role="tab"
              aria-selected={to_string(@grouping == "recipe")}
              phx-click="group"
              phx-value-by="recipe"
              class={[
                "min-h-11 flex-1 rounded-lg text-sm font-bold",
                @grouping == "recipe" && "bg-base-200 shadow-sm"
              ]}
            >
              By recipe
            </button>
          </div>
        </header>
        <.form
          for={@extra_form}
          id="extra-item-form"
          phx-submit="add_extra"
          class="flex items-start gap-2"
        >
          <div class="min-w-0 flex-1">
            <.input
              field={@extra_form[:name]}
              aria-label="Add an item"
              placeholder="Add something else (e.g. coffee)"
              maxlength="150"
              class="field !border-dashed"
            />
          </div>
          <button type="submit" class="action size-12 !p-0" aria-label="Add item">
            <.icon name="hero-plus" class="size-5" />
          </button>
        </.form>
        <div :if={@empty?} id="shopping-empty" class="surface space-y-3 p-7 text-center">
          <h2 class="text-xl">A fresh list</h2>
          <p class="text-sm text-muted">Plan some meals to fill your list, or add extras above.</p>
          <.link navigate={~p"/planner?week=#{Date.to_iso8601(@week_start)}"} class="action">
            Plan your meals
          </.link>
        </div>
        <div id="shopping-groups" phx-update="stream" class="space-y-4">
          <section
            :for={{id, group} <- @streams.groups}
            id={id}
            class="surface overflow-hidden !rounded-[18px]"
          >
            <div class={["flex items-center justify-between px-3.5 py-2.5", group.tone]}>
              <h2 class="text-[15px]">{group.name}</h2>
              <span class="text-xs font-bold">{length(group.items)} to get</span>
            </div>
            <button
              :for={item <- group.items}
              id={"#{id}-#{item.id}"}
              role="checkbox"
              aria-checked="false"
              phx-click="toggle_item"
              phx-value-id={item.id}
              class="flex min-h-15 w-full items-center gap-3.5 border-t border-base-300 px-3.5 py-2 text-left transition-colors hover:bg-tag"
            >
              <span class="size-[26px] shrink-0 rounded-lg border-2 border-checkbox"></span><span class="min-w-0 flex-1"><span class="block font-bold">{item.name}</span><span class="block text-xs text-muted">{if item.recipes == [], do: "Extra item", else: "For " <> Enum.join(item.recipes, ", ")}</span></span><span class="text-right text-sm text-secondary-ink">{item.quantity} {item.unit}</span>
            </button>
          </section>
        </div>
        <section aria-label="In the basket" class="space-y-2">
          <h2 class="eyebrow">In the basket · {@basket_count}</h2>
          <div id="basket" phx-update="stream">
            <button
              :for={{id, item} <- @streams.basket}
              id={id}
              role="checkbox"
              aria-checked="true"
              phx-click="toggle_item"
              phx-value-id={item.id}
              class="flex min-h-11 w-full items-center gap-3.5 rounded-xl px-2.5 py-1 text-left text-muted hover:bg-base-200"
            >
              <span class="flex size-[26px] shrink-0 items-center justify-center rounded-lg bg-primary text-primary-content">
                <.icon name="hero-check" class="size-4" />
              </span>
              <span class="flex-1 line-through">{item.name}</span><span class="text-sm">{item.quantity} {item.unit}</span>
            </button>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end

defmodule CookbookWeb.ShoppingListLive do
  use CookbookWeb, :live_view

  alias Cookbook.Planner

  def mount(params, _session, socket) do
    week_start =
      case params["week"] do
        nil -> Planner.normalize_to_monday(Date.utc_today())
        date_str -> Date.from_iso8601!(date_str) |> Planner.normalize_to_monday()
      end

    {:ok, plan} = Planner.get_or_create_plan_for_week(socket.assigns.current_user.id, week_start)
    shopping_list = Planner.generate_shopping_list(plan.id)

    {:ok,
     assign(socket,
       week_start: week_start,
       plan: plan,
       shopping_list: shopping_list,
       checked: MapSet.new(),
       page_title: "Shopping List"
     )}
  end

  def handle_event("toggle_item", %{"name" => name}, socket) do
    checked =
      if MapSet.member?(socket.assigns.checked, name) do
        MapSet.delete(socket.assigns.checked, name)
      else
        MapSet.put(socket.assigns.checked, name)
      end

    {:noreply, assign(socket, checked: checked)}
  end

  defp checked_count(shopping_list, checked) do
    Enum.count(shopping_list, fn item -> MapSet.member?(checked, item.name) end)
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto">
      <.header>
        Shopping List
        <:subtitle>Week of {Calendar.strftime(@week_start, "%B %d, %Y")}</:subtitle>
        <:actions>
          <.button navigate={~p"/planner?week=#{Date.to_iso8601(@week_start)}"}>
            <.icon name="hero-arrow-left" class="size-4 mr-1" /> Back to Planner
          </.button>
        </:actions>
      </.header>

      <div :if={@shopping_list == []} class="mt-16 text-center">
        <div class="flex items-center justify-center w-16 h-16 rounded-full bg-primary/10 mx-auto mb-4">
          <.icon name="hero-shopping-cart" class="size-8 text-primary" />
        </div>
        <p class="text-base-content/60 text-lg">No meals planned yet</p>
        <p class="text-base-content/40 text-sm mt-1">Add some recipes to your meal plan first</p>
        <.button navigate={~p"/planner?week=#{Date.to_iso8601(@week_start)}"} variant="primary" class="btn btn-primary mt-4">
          Go to Planner
        </.button>
      </div>

      <div :if={@shopping_list != []} class="mt-6">
        <%!-- Progress bar --%>
        <div class="flex items-center gap-3 mb-4">
          <div class="flex-1 h-2 rounded-full bg-base-300/50 overflow-hidden">
            <div
              class="h-full rounded-full bg-gradient-to-r from-primary to-secondary transition-all duration-300"
              style={"width: #{if @shopping_list == [], do: 0, else: checked_count(@shopping_list, @checked) / length(@shopping_list) * 100}%"}
            />
          </div>
          <span class="text-sm text-base-content/50 tabular-nums">
            {checked_count(@shopping_list, @checked)}/{length(@shopping_list)}
          </span>
        </div>

        <ul class="space-y-2">
          <li
            :for={item <- @shopping_list}
            class={[
              "flex items-center gap-3 p-3.5 rounded-xl border bg-base-200 cursor-pointer transition-all",
              MapSet.member?(@checked, item.name) && "border-base-300/30 opacity-50" || "border-base-300/50 hover:border-primary/30"
            ]}
            phx-click="toggle_item"
            phx-value-name={item.name}
          >
            <div class={[
              "flex items-center justify-center w-5 h-5 rounded-md border-2 shrink-0 transition-colors",
              MapSet.member?(@checked, item.name) && "bg-primary border-primary" || "border-base-300"
            ]}>
              <.icon :if={MapSet.member?(@checked, item.name)} name="hero-check" class="size-3 text-white" />
            </div>
            <div class="flex-1 min-w-0">
              <span class={[
                "font-medium",
                MapSet.member?(@checked, item.name) && "line-through text-base-content/40"
              ]}>
                {item.name}
              </span>
            </div>
            <div class="text-sm text-base-content/50 shrink-0">
              <span :if={item.quantity != ""}>{item.quantity}</span>
              <span :if={item.unit != ""} class="ml-0.5">{item.unit}</span>
            </div>
          </li>
        </ul>
      </div>
    </div>
    """
  end
end

defmodule CookbookWeb.CookModeLive do
  use CookbookWeb, :live_view

  alias Cookbook.{AI, Recipes}

  def mount(%{"id" => id}, _session, socket) do
    recipe = Recipes.get_recipe!(id)

    if recipe.steps == [] do
      {:ok,
       socket
       |> put_flash(:error, "This recipe has no steps to cook.")
       |> push_navigate(to: ~p"/recipes/#{recipe.id}")}
    else
      steps = Enum.sort_by(recipe.steps, & &1.position)

      {:ok,
       assign(socket,
         recipe: recipe,
         steps: steps,
         current_step: 0,
         total_steps: length(steps),
         show_ingredients: false,
         adjusted_ingredients: nil,
         adjusted_servings: nil,
         adjust_open: false,
         adjust_loading: false,
         adjust_error: nil,
         page_title: "Cook: #{recipe.title}"
       )}
    end
  end

  def handle_event("next", _params, socket) do
    %{current_step: current, total_steps: total} = socket.assigns
    {:noreply, assign(socket, current_step: min(current + 1, total - 1))}
  end

  def handle_event("prev", _params, socket) do
    %{current_step: current} = socket.assigns
    {:noreply, assign(socket, current_step: max(current - 1, 0))}
  end

  def handle_event("toggle-ingredients", _params, socket) do
    {:noreply, assign(socket, show_ingredients: !socket.assigns.show_ingredients)}
  end

  def handle_event("go-to-step", %{"step" => step}, socket) do
    step = String.to_integer(step)
    step = max(0, min(step, socket.assigns.total_steps - 1))
    {:noreply, assign(socket, current_step: step)}
  end

  def handle_event("open_adjust", _params, socket) do
    {:noreply, assign(socket, adjust_open: true, adjust_error: nil)}
  end

  def handle_event("close_adjust", _params, socket) do
    {:noreply, assign(socket, adjust_open: false, adjust_error: nil)}
  end

  def handle_event("reset_adjust", _params, socket) do
    {:noreply, assign(socket, adjusted_ingredients: nil, adjusted_servings: nil)}
  end

  def handle_event("adjust_quantities", %{"servings" => servings_str}, socket) do
    case Integer.parse(String.trim(servings_str)) do
      {servings, ""} when servings > 0 ->
        socket = assign(socket, adjust_loading: true, adjust_error: nil)
        self_pid = self()
        recipe = socket.assigns.recipe
        unit_system = socket.assigns.current_user.unit_system

        Task.start(fn ->
          result = AI.adjust_quantities(recipe, servings, unit_system)
          send(self_pid, {:adjust_result, result})
        end)

        {:noreply, socket}

      _ ->
        {:noreply, assign(socket, adjust_error: "Please enter a valid number of servings.")}
    end
  end

  def handle_info({:adjust_result, {:ok, %{ingredients: ingredients, servings: servings}}}, socket) do
    {:noreply,
     assign(socket,
       adjust_loading: false,
       adjust_open: false,
       adjusted_ingredients: ingredients,
       adjusted_servings: servings
     )}
  end

  def handle_info({:adjust_result, {:error, _reason}}, socket) do
    {:noreply,
     assign(socket,
       adjust_loading: false,
       adjust_error: "Failed to adjust quantities. Please try again."
     )}
  end

  def handle_event("keydown", %{"key" => "ArrowRight"}, socket) do
    %{current_step: current, total_steps: total} = socket.assigns
    {:noreply, assign(socket, current_step: min(current + 1, total - 1))}
  end

  def handle_event("keydown", %{"key" => "ArrowLeft"}, socket) do
    %{current_step: current} = socket.assigns
    {:noreply, assign(socket, current_step: max(current - 1, 0))}
  end

  def handle_event("keydown", %{"key" => "Escape"}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/recipes/#{socket.assigns.recipe.id}")}
  end

  def handle_event("keydown", _params, socket) do
    {:noreply, socket}
  end

  def render(assigns) do
    assigns = assign(assigns, :step, Enum.at(assigns.steps, assigns.current_step))

    ~H"""
    <div class="fixed inset-0 z-50 bg-base-100 flex flex-col" phx-window-keydown="keydown">
      <%!-- Top bar --%>
      <div class="flex items-center justify-between px-4 py-3 border-b border-base-300/50 bg-base-200/80 backdrop-blur-sm">
        <.link
          navigate={~p"/recipes/#{@recipe.id}"}
          class="btn btn-ghost btn-sm btn-circle"
          aria-label="Exit cook mode"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </.link>

        <div class="flex items-center gap-2 flex-1 justify-center px-2 min-w-0">
          <h1 class="text-lg font-semibold truncate">{@recipe.title}</h1>
          <span :if={@adjusted_servings} class="hidden sm:inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-primary/10 text-primary shrink-0">
            <.icon name="hero-sparkles" class="size-3" />
            {@adjusted_servings} servings
          </span>
        </div>

        <div class="flex items-center gap-1 shrink-0">
          <button
            :if={@adjusted_servings}
            phx-click="reset_adjust"
            class="btn btn-ghost btn-sm text-base-content/50 hidden sm:flex"
            aria-label="Reset to original quantities"
          >
            Reset
          </button>
          <button
            phx-click="open_adjust"
            class="btn btn-ghost btn-sm"
            aria-label="Adjust quantities"
          >
            <.icon name="hero-sparkles" class="size-5" />
            <span class="hidden sm:inline ml-1">Adjust</span>
          </button>
          <button
            :if={@recipe.ingredients != []}
            phx-click="toggle-ingredients"
            class="btn btn-ghost btn-sm"
            aria-label="Toggle ingredients"
          >
            <.icon name="hero-clipboard-document-list" class="size-5" />
            <span class="hidden sm:inline ml-1">Ingredients</span>
          </button>
          <span :if={@recipe.ingredients == []} class="w-10"></span>
        </div>
      </div>

      <%!-- Main step content --%>
      <div class="flex-1 flex flex-col items-center justify-center px-6 py-8 overflow-y-auto">
        <p class="text-sm font-medium text-base-content/50 mb-4">
          Step {@current_step + 1} of {@total_steps}
        </p>

        <p class="text-2xl sm:text-3xl md:text-4xl leading-relaxed text-center max-w-3xl">
          {@step.instruction}
        </p>

        <div
          :if={@step.duration_minutes}
          class="mt-6 inline-flex items-center gap-2 px-4 py-2 rounded-full bg-primary/10 text-primary text-sm font-medium"
        >
          <.icon name="hero-clock" class="size-4" />
          {@step.duration_minutes} min
        </div>
      </div>

      <%!-- Bottom bar: progress dots + nav buttons --%>
      <div class="border-t border-base-300/50 bg-base-200/80 backdrop-blur-sm px-4 py-4">
        <%!-- Progress dots --%>
        <div class="flex items-center justify-center gap-2 mb-4">
          <button
            :for={i <- 0..(@total_steps - 1)}
            phx-click="go-to-step"
            phx-value-step={i}
            class={[
              "rounded-full transition-all duration-200",
              if(i == @current_step,
                do: "w-6 h-2.5 bg-primary",
                else: "w-2.5 h-2.5 bg-base-content/20 hover:bg-base-content/40"
              )
            ]}
            aria-label={"Go to step #{i + 1}"}
          />
        </div>

        <%!-- Navigation buttons --%>
        <div class="flex gap-3 max-w-lg mx-auto">
          <button
            phx-click="prev"
            disabled={@current_step == 0}
            class="btn btn-lg flex-1 disabled:opacity-30"
          >
            <.icon name="hero-chevron-left" class="size-5 mr-1" /> Previous
          </button>
          <button
            phx-click="next"
            disabled={@current_step == @total_steps - 1}
            class="btn btn-lg btn-primary flex-1 disabled:opacity-30"
          >
            Next <.icon name="hero-chevron-right" class="size-5 ml-1" />
          </button>
        </div>
      </div>

      <%!-- Ingredients drawer --%>
      <div
        :if={@show_ingredients}
        class="fixed inset-0 z-60"
        phx-click="toggle-ingredients"
      >
        <%!-- Backdrop --%>
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" />

        <%!-- Drawer panel --%>
        <div
          class="absolute top-0 right-0 h-full w-80 max-w-[85vw] bg-base-100 shadow-2xl flex flex-col"
          phx-click-away="toggle-ingredients"
        >
          <div class="flex items-center justify-between px-5 py-4 border-b border-base-300/50">
            <div>
              <h2 class="text-lg font-semibold">Ingredients</h2>
              <p :if={@adjusted_servings} class="text-xs text-primary mt-0.5 flex items-center gap-1">
                <.icon name="hero-sparkles" class="size-3" />
                Adjusted for {@adjusted_servings} servings
              </p>
            </div>
            <button
              phx-click="toggle-ingredients"
              class="btn btn-ghost btn-sm btn-circle"
              aria-label="Close ingredients"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <div class="flex-1 overflow-y-auto px-5 py-4">
            <ul class="space-y-3">
              <li :for={ingredient <- @adjusted_ingredients || @recipe.ingredients} class="flex items-start gap-3 text-lg">
                <span class="w-2 h-2 rounded-full bg-primary mt-2.5 shrink-0"></span>
                <span>
                  <span :if={ingredient.quantity && ingredient.quantity != ""} class="font-medium">{ingredient.quantity}</span>
                  <span :if={ingredient.unit && ingredient.unit != ""} class="text-base-content/60">{ingredient.unit}</span>
                  {ingredient.name}
                </span>
              </li>
            </ul>
          </div>
        </div>
      </div>

      <%!-- Adjust quantities modal --%>
      <div :if={@adjust_open} class="fixed inset-0 z-[70] flex items-center justify-center px-4">
        <%!-- Backdrop --%>
        <div class="absolute inset-0 bg-black/40 backdrop-blur-sm" phx-click="close_adjust" />

        <%!-- Modal panel --%>
        <div class="relative w-full max-w-sm bg-base-100 rounded-2xl shadow-2xl p-6 space-y-5 z-10">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <div class="flex items-center justify-center w-8 h-8 rounded-lg bg-primary/10">
                <.icon name="hero-sparkles" class="size-4 text-primary" />
              </div>
              <h2 class="text-lg font-semibold">Adjust quantities</h2>
            </div>
            <button phx-click="close_adjust" class="btn btn-ghost btn-sm btn-circle" aria-label="Close">
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>

          <p class="text-sm text-base-content/60">
            This recipe makes <span class="font-medium text-base-content">{@recipe.servings || "?"} servings</span>.
            Enter your desired serving count and AI will scale the ingredients.
          </p>

          <form phx-submit="adjust_quantities" class="space-y-4">
            <div>
              <label class="label mb-1 text-sm font-medium">Target servings</label>
              <input
                type="number"
                name="servings"
                min="1"
                value={@recipe.servings}
                placeholder="e.g. 2"
                class="input input-bordered w-full"
                disabled={@adjust_loading}
                autofocus
              />
            </div>

            <div :if={@adjust_error} class="alert alert-error py-2 text-sm">
              <.icon name="hero-exclamation-triangle" class="size-4 shrink-0" />
              {@adjust_error}
            </div>

            <button type="submit" class="btn btn-primary w-full" disabled={@adjust_loading}>
              <%= if @adjust_loading do %>
                <span class="loading loading-spinner loading-sm"></span>
                Adjusting quantities...
              <% else %>
                <.icon name="hero-sparkles" class="size-4 mr-1" />
                Adjust with AI
              <% end %>
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end
end

defmodule CookbookWeb.RecipeShowLive do
  use CookbookWeb, :live_view
  alias Cookbook.Recipes
  alias Cookbook.Recipes.Scaling
  alias Cookbook.Recipes.Step

  def mount(%{"id" => id}, _session, socket) do
    recipe = Recipes.get_recipe!(socket.assigns.current_user.id, id)

    if recipe.user_id != socket.assigns.current_user.id do
      {:ok, push_navigate(socket, to: ~p"/recipes")}
    else
      {:ok,
       socket
       |> assign(
         recipe: recipe,
         page_title: recipe.title,
         adjust_open: false,
         adjust_loading: false,
         adjust_error: nil,
         adjusted_servings: nil,
         adjust_form: to_form(%{"servings" => recipe.servings || 2})
       )
       |> ingredients(recipe.ingredients)
       |> stream(:steps, recipe.steps), layout: false}
    end
  end

  def handle_event("delete", _, socket) do
    Recipes.delete_recipe(socket.assigns.current_user.id, socket.assigns.recipe.id)
    {:noreply, push_navigate(socket, to: ~p"/recipes")}
  end

  def handle_event("open_adjust", _, socket),
    do: {:noreply, assign(socket, adjust_open: true, adjust_error: nil)}

  def handle_event("close_adjust", _, socket), do: {:noreply, assign(socket, adjust_open: false)}

  def handle_event("reset_adjust", _, socket),
    do:
      {:noreply,
       socket |> assign(adjusted_servings: nil) |> ingredients(socket.assigns.recipe.ingredients)}

  def handle_event("adjust_quantities", %{"servings" => value}, socket) do
    case Integer.parse(String.trim(value)) do
      {servings, ""} when servings > 0 and servings <= 100 ->
        recipe = socket.assigns.recipe

        case Scaling.scale(recipe, servings) do
          {:ok, %{ingredients: list, servings: servings}} ->
            {:noreply,
             socket
             |> assign(adjust_open: false, adjusted_servings: servings, adjust_error: nil)
             |> ingredients(list)}

          {:error, _} ->
            {:noreply,
             assign(socket,
               adjust_error:
                 "Set the recipe's original serving count before adjusting quantities."
             )}
        end

      _ ->
        {:noreply, assign(socket, adjust_error: "Enter a serving count between 1 and 100.")}
    end
  end

  defp ingredients(socket, list) do
    list =
      list
      |> Enum.with_index()
      |> Enum.map(fn {ingredient, i} -> %{id: i, ingredient: ingredient} end)

    stream(socket, :ingredients, list, reset: true)
  end

  def render(assigns) do
    ~H"""
    <Layouts.app {assigns}>
      <article id="recipe-detail" class="mx-auto max-w-5xl space-y-7">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <.link navigate="/recipes" class="action">
            <.icon name="hero-arrow-left" class="size-4" />Recipes
          </.link>
          <div class="flex gap-2">
            <.link navigate={~p"/recipes/#{@recipe.id}/edit"} aria-label="Edit recipe" class="action">
              <.icon name="hero-pencil-square" class="size-4" />Edit
            </.link>
            <button
              id="delete-recipe"
              phx-click="delete"
              data-confirm="Delete this recipe? This cannot be undone."
              aria-label="Delete recipe"
              class="action size-11 !p-0"
            ><.icon name="hero-trash" class="size-5" /></button>
          </div>
        </div>
        <div class="grid items-start gap-7 lg:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]">
          <div class="flex aspect-[4/3] items-center justify-center overflow-hidden rounded-[20px] bg-peach">
            <img
              :if={@recipe.image_url}
              src={@recipe.image_url}
              alt={@recipe.title}
              class="size-full object-cover"
            />
            <div
              :if={!@recipe.image_url}
              class="flex size-36 items-center justify-center rounded-full border-[18px] border-base-100 bg-base-200"
            >
              <.icon name="hero-cake" class="size-14 text-peach-ink" />
            </div>
          </div>
          <header class="space-y-5">
            <p class="eyebrow">From your collection</p>
            <h1 class="text-3xl leading-tight sm:text-4xl">{@recipe.title}</h1>
            <p :if={@recipe.description} class="leading-relaxed text-secondary-ink">
              {@recipe.description}
            </p>
            <div class="flex flex-wrap gap-2">
              <span
                :if={@recipe.total_time_minutes}
                class="rounded-full bg-butter px-3 py-1.5 text-sm text-butter-ink"
              >
                {@recipe.total_time_minutes} min
              </span>
              <span
                :if={@recipe.servings}
                class="rounded-full bg-sage px-3 py-1.5 text-sm text-sage-ink"
              >Serves {@adjusted_servings || @recipe.servings}</span><span
                :for={tag <- @recipe.tags}
                class="rounded-full bg-tag px-3 py-1.5 text-sm text-secondary-ink"
              >{tag}</span>
            </div>
            <div class="flex flex-wrap gap-2.5">
              <.link
                :if={@recipe.steps != []}
                id="detail-cook"
                navigate={~p"/recipes/#{@recipe.id}/cook"}
                class="action action-primary"
              >
                <.icon name="hero-play" class="size-5" />Start cooking
              </.link>
              <button id="detail-adjust" phx-click="open_adjust" class="action"><.icon
                name="hero-sparkles"
                class="size-4"
              />Adjust servings</button><button
                phx-click={JS.dispatch("cookbook:print")}
                class="action"
              ><.icon name="hero-printer" class="size-4" />Print</button>
            </div>
            <p :if={@adjusted_servings} class="text-sm text-muted">
              Adjusted for {@adjusted_servings} servings.
              <button phx-click="reset_adjust" class="inline-flex min-h-11 items-center underline">
                Reset amounts
              </button>
            </p>
          </header>
        </div>
        <div class="grid items-start gap-7 lg:grid-cols-[minmax(0,2fr)_minmax(0,3fr)]">
          <section class="surface p-5 sm:p-6">
            <h2 class="mb-4 text-xl">Ingredients</h2>
            <ul id="detail-ingredients" phx-update="stream" class="divide-y divide-base-300">
              <li
                :for={{id, row} <- @streams.ingredients}
                id={id}
                class="flex items-baseline gap-3 py-3"
              >
                <strong class="min-w-16 text-sm">
                  {row.ingredient.quantity} {row.ingredient.unit}
                </strong>
                <span>{row.ingredient.name}</span>
              </li>
            </ul>
          </section>
          <section class="space-y-5">
            <h2 class="text-xl">Method</h2>
            <ol id="detail-steps" phx-update="stream" class="space-y-5">
              <li :for={{id, step} <- @streams.steps} id={id} class="surface space-y-2 p-5">
                <h3 class="text-lg">{step.position + 1}. {Step.title(step)}</h3>
                <p class="leading-relaxed text-secondary-ink">{step.instruction}</p>
                <p :if={step.duration_minutes} class="text-sm text-muted">
                  About {step.duration_minutes} min
                </p>
              </li>
            </ol>
          </section>
        </div>
        <section :if={@recipe.notes} class="rounded-[20px] bg-butter p-6 text-butter-ink">
          <h2 class="mb-2 text-lg">Kitchen notes</h2>
          <p class="whitespace-pre-line leading-relaxed">{@recipe.notes}</p>
        </section>
        <a
          :if={@recipe.source_url}
          href={@recipe.source_url}
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex min-h-11 items-center gap-2 text-sm underline"
        >
          View original source <.icon name="hero-arrow-top-right-on-square" class="size-4" />
        </a>
      </article>
      <div
        :if={@adjust_open}
        id="adjust-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="adjust-title"
        class="fixed inset-0 z-50 flex items-center justify-center p-5"
      >
        <div class="absolute inset-0 bg-black/50" phx-click="close_adjust"></div>
        <section
          class="surface relative w-full max-w-sm space-y-5 p-6"
          phx-window-keydown="close_adjust"
          phx-key="Escape"
        >
          <div class="flex items-center justify-between">
            <h2 id="adjust-title" class="text-xl">Adjust servings</h2>
            <button phx-click="close_adjust" aria-label="Close" class="action size-11 !p-0">
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>
          <p class="text-sm text-muted">
            Numeric ingredient amounts scale locally. Non-numeric amounts and your saved recipe stay unchanged.
          </p>
          <.form for={@adjust_form} id="adjust-form" phx-submit="adjust_quantities" class="space-y-4">
            <.input
              field={@adjust_form[:servings]}
              type="number"
              min="1"
              max="100"
              label="Servings"
              disabled={@adjust_loading}
              class="field"
            />
            <p
              :if={@adjust_error}
              id="adjust-error"
              role="alert"
              class="rounded-xl bg-blush p-3 text-sm text-blush-ink"
            >
              {@adjust_error}
            </p>
            <button type="submit" disabled={@adjust_loading} class="action action-primary w-full">
              Adjust servings
            </button>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end
end

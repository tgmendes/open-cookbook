defmodule CookbookWeb.Layouts do
  use CookbookWeb, :html
  embed_templates "layouts/*"

  defp nav_active?(current, "/"), do: current == "/"
  defp nav_active?(current, "/planner"), do: current == "/planner"
  defp nav_active?(current, path), do: String.starts_with?(current, path)

  attr :flash, :map, required: true
  attr :current_scope, :map, default: nil
  attr :current_user, :any, default: nil
  attr :nav_path, :string, default: ""
  attr :navigation, :map, default: %{tonight: nil, shopping_count: 0}
  attr :page_full_width, :boolean, default: false
  attr :inner_content, :any, default: nil
  attr :immersive, :boolean, default: false
  slot :inner_block

  def app(assigns) do
    assigns =
      assigns
      |> assign_new(:inner_block, fn -> [] end)
      |> assign_new(:inner_content, fn -> nil end)
      |> assign_new(:current_user, fn -> nil end)
      |> assign_new(:nav_path, fn -> "" end)
      |> assign_new(:immersive, fn -> false end)
      |> assign_new(:page_full_width, fn -> false end)
      |> assign_new(:navigation, fn -> %{tonight: nil, shopping_count: 0} end)

    assigns =
      assign(assigns, :links, [
        {"/", "Today", "Today", "hero-home"},
        {"/recipes", "Recipes", "Recipes", "hero-book-open"},
        {"/planner", "Meal plan", "Plan", "hero-calendar-days"},
        {"/planner/shopping", "Shopping list", "Shop", "hero-shopping-cart"}
      ])

    ~H"""
    <div class="min-h-dvh">
      <aside
        :if={@current_user && !@immersive}
        id="sidebar"
        class="fixed inset-y-0 left-0 z-30 hidden w-[248px] flex-col border-r border-base-300 bg-base-100 px-[18px] py-7 lg:flex"
      >
        <.link navigate="/" class="mb-7 flex min-h-11 items-center gap-2.5">
          <span class="flex size-9 shrink-0 items-center justify-center rounded-xl bg-primary text-primary-content">
            <.icon name="hero-book-open" class="size-5" />
          </span>
          <span class="font-heading text-[19px] font-semibold tracking-tight">Open Cookbook</span>
        </.link>
        <nav aria-label="Main" class="space-y-1">
          <.link
            :for={{path, label, _, icon} <- @links}
            navigate={path}
            aria-current={nav_active?(@nav_path, path) && "page"}
            class={[
              "flex min-h-11 items-center gap-3 rounded-xl px-3.5 text-[15px] transition-colors",
              if(nav_active?(@nav_path, path),
                do: "bg-teal-tint font-bold text-teal-ink",
                else: "text-secondary-ink hover:bg-base-200"
              )
            ]}
          >
            <.icon name={icon} class="size-5 shrink-0" /><span class="flex-1">{label}</span>
            <span
              :if={path == "/planner/shopping"}
              id="shopping-count"
              class="rounded-full bg-count px-2 text-xs font-bold text-count-ink"
            >
              {@navigation.shopping_count}
            </span>
          </.link>
        </nav>
        <div class="mt-auto space-y-3 pt-8">
          <section :if={@navigation.tonight} id="up-next" class="surface space-y-2 p-3.5">
            <p class="eyebrow">Up next</p>
            <h2 class="text-[15px]">{@navigation.tonight.title}</h2>
            <p class="text-sm text-muted">
              Tonight
              <span :if={@navigation.tonight.cook_time_minutes}>
                · {@navigation.tonight.cook_time_minutes} min
              </span>
            </p>
            <.link
              navigate={~p"/recipes/#{@navigation.tonight.id}/cook"}
              class="action action-primary w-full"
            >
              Start cooking
            </.link>
          </section>
          <.link
            id="desktop-settings"
            navigate="/settings"
            class="flex min-h-11 items-center gap-2.5 rounded-xl px-3.5 text-sm text-secondary-ink hover:bg-base-200"
          >
            <.icon name="hero-cog-6-tooth" class="size-5" />Settings · {@current_user.unit_system}
          </.link>
        </div>
      </aside>
      <div class={[@current_user && !@immersive && "lg:pl-[248px]"]}>
        <div
          :if={@current_user && !@immersive}
          class="flex items-center justify-between px-5 pt-4 lg:hidden"
        >
          <.link navigate="/" class="inline-flex min-h-11 items-center font-heading font-semibold">
            Open Cookbook
          </.link>
          <.link
            navigate="/settings"
            class="flex size-11 items-center justify-center rounded-xl hover:bg-base-200"
            aria-label="Settings"
          >
            <.icon name="hero-cog-6-tooth" class="size-5" />
          </.link>
        </div>
        <main class={[
          "min-w-0",
          !@immersive && "px-5 pt-6 pb-28 sm:px-8 lg:px-10 lg:pt-9 lg:pb-14",
          @immersive && "min-h-dvh",
          @page_full_width && "lg:px-8"
        ]}>
          <div class={[!@immersive && "mx-auto max-w-[1320px]"]}>
            <%= if @inner_block != [] do %>
              {render_slot(@inner_block)}
            <% else %>
              {@inner_content}
            <% end %>
          </div>
        </main>
      </div>
    </div>
    <.flash_group flash={@flash} />
    <nav
      :if={@current_user && !@immersive}
      id="phone-tabs"
      aria-label="Main"
      class="fixed inset-x-0 bottom-0 z-40 flex border-t border-base-300 bg-base-200 px-2 pt-1.5 pb-[max(12px,env(safe-area-inset-bottom))] lg:hidden"
    >
      <.link
        :for={{path, _, label, icon} <- @links}
        navigate={path}
        aria-current={nav_active?(@nav_path, path) && "page"}
        class={[
          "flex min-h-12 flex-1 flex-col items-center justify-center gap-1 text-xs font-bold",
          if(nav_active?(@nav_path, path), do: "text-teal-ink", else: "text-muted")
        ]}
      >
        <span class={[
          "flex justify-center rounded-full px-4 py-0.5",
          nav_active?(@nav_path, path) && "bg-teal-tint"
        ]}><.icon name={icon} class="size-[22px]" /></span>{label}
      </.link>
    </nav>
    """
  end

  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end

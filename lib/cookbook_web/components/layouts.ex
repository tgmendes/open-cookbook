defmodule CookbookWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use CookbookWeb, :html

  embed_templates "layouts/*"

  defp nav_active?(assigns, path) do
    current = assigns[:nav_path] || ""

    case path do
      "/recipes" ->
        current == "/" || current == "/recipes" ||
          String.starts_with?(current, "/recipes/")

      "/planner" ->
        (current == "/planner" || String.starts_with?(current, "/planner/")) &&
          !String.starts_with?(current, "/planner/shopping")

      "/planner/shopping" ->
        current == "/planner/shopping"

      _ ->
        false
    end
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current scope"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="min-h-screen">
      <%!-- Desktop sidebar --%>
      <aside
        :if={assigns[:current_user]}
        class="hidden lg:flex lg:flex-col lg:fixed lg:inset-y-0 lg:w-56 border-r border-base-300/50 bg-base-100 z-30"
      >
        <div class="px-5 py-5">
          <a href="/" class="flex items-center gap-2.5">
            <span class="flex items-center justify-center w-8 h-8 rounded-lg bg-gradient-to-br from-primary to-secondary text-primary-content shadow-sm shrink-0">
              <.icon name="hero-book-open-solid" class="size-4" />
            </span>
            <span class="font-bold text-base bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent">
              Open Cookbook
            </span>
          </a>
        </div>

        <nav class="flex-1 px-3 pb-3 space-y-0.5 overflow-y-auto">
          <.link
            navigate="/recipes"
            class={[
              "flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-medium transition-all duration-200",
              nav_active?(assigns, "/recipes") &&
                "bg-primary/10 text-primary" ||
                "text-base-content/60 hover:text-base-content hover:bg-base-300/50"
            ]}
          >
            <.icon name="hero-book-open" class="size-4 shrink-0" />
            Recipes
          </.link>
          <.link
            navigate="/planner"
            class={[
              "flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-medium transition-all duration-200",
              nav_active?(assigns, "/planner") &&
                "bg-primary/10 text-primary" ||
                "text-base-content/60 hover:text-base-content hover:bg-base-300/50"
            ]}
          >
            <.icon name="hero-calendar-days" class="size-4 shrink-0" />
            Meal Plan
          </.link>
          <.link
            navigate="/planner/shopping"
            class={[
              "flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm font-medium transition-all duration-200",
              nav_active?(assigns, "/planner/shopping") &&
                "bg-primary/10 text-primary" ||
                "text-base-content/60 hover:text-base-content hover:bg-base-300/50"
            ]}
          >
            <.icon name="hero-shopping-cart" class="size-4 shrink-0" />
            Shopping List
          </.link>
        </nav>

        <div class="px-3 py-4 border-t border-base-300/50 space-y-0.5">
          <button
            phx-click="toggle_unit_system"
            class="w-full flex items-center gap-3 px-3 py-2 rounded-xl text-sm text-base-content/50 hover:text-base-content hover:bg-base-300/50 transition-all duration-200"
            title={"Switch to #{if assigns[:current_user] && assigns[:current_user].unit_system == "metric", do: "imperial", else: "metric"} units"}
          >
            <.icon name="hero-scale" class="size-4 shrink-0" />
            <span class="capitalize">{assigns[:current_user] && assigns[:current_user].unit_system || "metric"}</span>
          </button>
          <a
            href="/auth/logout"
            class="flex items-center gap-3 px-3 py-2 rounded-xl text-sm text-base-content/50 hover:text-base-content hover:bg-base-300/50 transition-all duration-200"
          >
            <.icon name="hero-arrow-right-on-rectangle" class="size-4 shrink-0" />
            Log out
          </a>
          <.link
            navigate="/recipes/new"
            class="mt-3 flex items-center justify-center gap-2 w-full py-2.5 rounded-xl bg-primary text-primary-content text-sm font-semibold hover:bg-primary/90 transition-colors"
          >
            <.icon name="hero-plus" class="size-4" />
            New Recipe
          </.link>
        </div>
      </aside>

      <%!-- Mobile top bar --%>
      <header
        :if={assigns[:current_user]}
        class="lg:hidden bg-base-100/80 backdrop-blur-md border-b border-base-300/50 sticky top-0 z-40"
      >
        <div class="flex items-center justify-between h-14 px-4">
          <a href="/" class="flex items-center gap-2">
            <span class="flex items-center justify-center w-7 h-7 rounded-lg bg-gradient-to-br from-primary to-secondary text-primary-content shadow-sm">
              <.icon name="hero-book-open-solid" class="size-3.5" />
            </span>
            <span class="font-bold text-sm bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent">
              Open Cookbook
            </span>
          </a>
          <button
            class="flex items-center justify-center w-9 h-9 rounded-lg hover:bg-base-300/50 transition-colors"
            phx-click={toggle_mobile_nav()}
            aria-label="Toggle menu"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
        </div>
      </header>

      <%!-- Mobile nav drawer --%>
      <div
        :if={assigns[:current_user]}
        id="mobile-nav"
        class="lg:hidden hidden border-b border-base-300/50 bg-base-100/95 backdrop-blur-md sticky top-14 z-30"
      >
        <nav class="px-4 py-3 flex flex-col gap-0.5">
          <.link
            navigate="/recipes"
            class={[
              "flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-sm font-medium transition-all",
              nav_active?(assigns, "/recipes") &&
                "bg-primary/10 text-primary" ||
                "text-base-content/60 hover:text-base-content hover:bg-base-300/50"
            ]}
          >
            <.icon name="hero-book-open" class="size-4" /> Recipes
          </.link>
          <.link
            navigate="/planner"
            class={[
              "flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-sm font-medium transition-all",
              nav_active?(assigns, "/planner") &&
                "bg-primary/10 text-primary" ||
                "text-base-content/60 hover:text-base-content hover:bg-base-300/50"
            ]}
          >
            <.icon name="hero-calendar-days" class="size-4" /> Meal Plan
          </.link>
          <.link
            navigate="/planner/shopping"
            class={[
              "flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-sm font-medium transition-all",
              nav_active?(assigns, "/planner/shopping") &&
                "bg-primary/10 text-primary" ||
                "text-base-content/60 hover:text-base-content hover:bg-base-300/50"
            ]}
          >
            <.icon name="hero-shopping-cart" class="size-4" /> Shopping List
          </.link>
          <div class="h-px bg-base-content/10 my-1"></div>
          <button
            phx-click="toggle_unit_system"
            class="w-full text-left flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-sm text-base-content/50 hover:text-base-content hover:bg-base-300/50 transition-all"
          >
            <.icon name="hero-scale" class="size-4" />
            Units: <span class="capitalize ml-1">{assigns[:current_user] && assigns[:current_user].unit_system || "metric"}</span>
          </button>
          <a
            href="/auth/logout"
            class="flex items-center gap-3 px-3.5 py-2.5 rounded-xl text-sm text-base-content/50 hover:text-base-content hover:bg-base-300/50 transition-all"
          >
            <.icon name="hero-arrow-right-on-rectangle" class="size-4" /> Log out
          </a>
        </nav>
      </div>

      <%!-- Main content with sidebar offset on desktop --%>
      <div class={[assigns[:current_user] && "lg:pl-56"]}>
        <main class="px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
          <div class="mx-auto max-w-5xl">
            {@inner_content}
          </div>
        </main>
      </div>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  defp toggle_mobile_nav(js \\ %JS{}) do
    js
    |> JS.toggle(
      to: "#mobile-nav",
      in: {"transition-all duration-200 ease-out", "opacity-0 -translate-y-2", "opacity-100 translate-y-0"},
      out: {"transition-all duration-150 ease-in", "opacity-100 translate-y-0", "opacity-0 -translate-y-2"}
    )
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

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

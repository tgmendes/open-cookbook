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
      "/" -> current == "/"
      "/recipes" -> current == "/recipes" || String.starts_with?(current, "/recipes/")
      "/planner" -> current == "/planner" || String.starts_with?(current, "/planner/")
      _ -> false
    end
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current scope"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="bg-base-200/60 backdrop-blur-md border-b border-base-300/50 sticky top-0 z-40">
      <div class="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex items-center justify-between h-16">
          <a href="/" class="flex items-center gap-2.5 font-bold text-lg group">
            <span class="flex items-center justify-center w-9 h-9 rounded-xl bg-gradient-to-br from-primary to-secondary text-primary-content shadow-sm">
              <.icon name="hero-book-open-solid" class="size-5" />
            </span>
            <span class="bg-gradient-to-r from-primary to-secondary bg-clip-text text-transparent">
              Cookbook
            </span>
          </a>
          <%!-- Desktop nav --%>
          <nav :if={assigns[:current_user]} class="hidden sm:flex items-center gap-1">
            <.link
              navigate="/"
              class={[
                "px-3.5 py-2 rounded-lg text-sm font-medium transition-all duration-200",
                nav_active?(assigns, "/") && "bg-primary text-primary-content shadow-sm" || "text-base-content/60 hover:text-base-content hover:bg-base-300/50"
              ]}
            >
              Dashboard
            </.link>
            <.link
              navigate="/recipes"
              class={[
                "px-3.5 py-2 rounded-lg text-sm font-medium transition-all duration-200",
                nav_active?(assigns, "/recipes") && "bg-primary text-primary-content shadow-sm" || "text-base-content/60 hover:text-base-content hover:bg-base-300/50"
              ]}
            >
              Recipes
            </.link>
            <.link
              navigate="/planner"
              class={[
                "px-3.5 py-2 rounded-lg text-sm font-medium transition-all duration-200",
                nav_active?(assigns, "/planner") && "bg-primary text-primary-content shadow-sm" || "text-base-content/60 hover:text-base-content hover:bg-base-300/50"
              ]}
            >
              Planner
            </.link>
            <div class="w-px h-5 bg-base-content/10 mx-2"></div>
            <a href="/auth/logout" class="px-3 py-2 rounded-lg text-sm text-base-content/40 hover:text-base-content hover:bg-base-300/50 transition-all duration-200">
              Log out
            </a>
          </nav>
          <%!-- Mobile hamburger --%>
          <button
            :if={assigns[:current_user]}
            class="sm:hidden flex items-center justify-center w-10 h-10 rounded-lg hover:bg-base-300/50 transition-colors"
            phx-click={toggle_mobile_nav()}
            aria-label="Toggle menu"
          >
            <.icon name="hero-bars-3" class="size-6" />
          </button>
        </div>
      </div>
      <%!-- Mobile nav drawer --%>
      <div
        :if={assigns[:current_user]}
        id="mobile-nav"
        class="sm:hidden hidden border-t border-base-300/50 bg-base-200/95 backdrop-blur-md"
      >
        <nav class="max-w-5xl mx-auto px-4 py-3 flex flex-col gap-1">
          <.link
            navigate="/"
            class={[
              "px-3.5 py-2.5 rounded-lg text-sm font-medium transition-all duration-200",
              nav_active?(assigns, "/") && "bg-primary text-primary-content shadow-sm" || "text-base-content/60 hover:text-base-content hover:bg-base-300/50"
            ]}
          >
            <.icon name="hero-home" class="size-4 mr-2 inline" /> Dashboard
          </.link>
          <.link
            navigate="/recipes"
            class={[
              "px-3.5 py-2.5 rounded-lg text-sm font-medium transition-all duration-200",
              nav_active?(assigns, "/recipes") && "bg-primary text-primary-content shadow-sm" || "text-base-content/60 hover:text-base-content hover:bg-base-300/50"
            ]}
          >
            <.icon name="hero-book-open" class="size-4 mr-2 inline" /> Recipes
          </.link>
          <.link
            navigate="/planner"
            class={[
              "px-3.5 py-2.5 rounded-lg text-sm font-medium transition-all duration-200",
              nav_active?(assigns, "/planner") && "bg-primary text-primary-content shadow-sm" || "text-base-content/60 hover:text-base-content hover:bg-base-300/50"
            ]}
          >
            <.icon name="hero-calendar-days" class="size-4 mr-2 inline" /> Planner
          </.link>
          <div class="h-px bg-base-content/10 my-1"></div>
          <a href="/auth/logout" class="px-3.5 py-2.5 rounded-lg text-sm text-base-content/40 hover:text-base-content hover:bg-base-300/50 transition-all duration-200">
            <.icon name="hero-arrow-right-on-rectangle" class="size-4 mr-2 inline" /> Log out
          </a>
        </nav>
      </div>
    </header>

    <main class="px-4 py-8 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-5xl">
        {render_slot(@inner_block)}
      </div>
    </main>

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

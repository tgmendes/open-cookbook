defmodule CookbookWeb.SettingsLive do
  use CookbookWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Settings"), layout: false}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app {assigns}>
      <div class="mx-auto max-w-xl space-y-7">
        <header>
          <h1 class="text-3xl sm:text-4xl">Settings</h1>
          <p class="mt-2 text-muted">Make this kitchen yours.</p>
        </header>
        <section class="surface space-y-6 p-6" aria-label="Preferences">
          <div class="flex items-center justify-between gap-4">
            <div>
              <h2 class="text-lg">Appearance</h2>
              <p class="text-sm text-muted">Choose light or dark for this device.</p>
            </div>
            <button id="theme-toggle" class="action" phx-click={JS.dispatch("toggle-theme")}>
              <.icon name="hero-sun" class="size-5 dark:hidden" /><.icon
                name="hero-moon"
                class="hidden size-5 dark:block"
              /> Switch theme
            </button>
          </div>
          <div class="flex items-center justify-between gap-4 border-t border-base-300 pt-6">
            <div>
              <h2 class="text-lg">Measurements</h2>
              <p class="text-sm text-muted">Units used for ingredient adjustments.</p>
            </div>
            <button id="unit-toggle" class="action capitalize" phx-click="toggle_unit_system">
              {@current_user.unit_system}
            </button>
          </div>
        </section>
        <a href="/auth/logout" class="action">
          Log out <.icon name="hero-arrow-right-on-rectangle" class="size-5" />
        </a>
      </div>
    </Layouts.app>
    """
  end
end

defmodule CookbookWeb.LoginLive do
  use CookbookWeb, :live_view
  alias Cookbook.{Accounts, Mailer}
  import Swoosh.Email

  def mount(_params, session, socket) do
    if CookbookWeb.Auth.session_user(session) do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      {:ok,
       assign(socket,
         page_title: "Sign in",
         form: to_form(%{"email" => ""}, as: :login),
         sent: false,
         delivery_error: false
       ), layout: false}
    end
  end

  def handle_event("send_magic_link", %{"login" => %{"email" => email}}, socket) do
    case Accounts.request_login_token(email) do
      {:ok, user, raw_token} ->
        link = url(socket, ~p"/auth/callback?token=#{raw_token}")

        result =
          new()
          |> to(user.email)
          |> from({"Cookbook", System.get_env("MAIL_FROM", "onboarding@resend.dev")})
          |> subject("Your magic login link")
          |> text_body("Click here to log in: #{link}\n\nThis link expires in 10 minutes.")
          |> html_body(
            "<h2>Sign in to Open Cookbook</h2><p><a href=\"#{link}\">Sign in to your cookbook</a></p><p>This link expires in 10 minutes.</p>"
          )
          |> Mailer.deliver()

        case result do
          {:ok, _} -> {:noreply, assign(socket, sent: true, delivery_error: false)}
          {:error, _} -> {:noreply, assign(socket, sent: false, delivery_error: true)}
        end

      {:error, reason} when reason in [:unauthorized, :rate_limited] ->
        {:noreply, assign(socket, sent: true)}

      {:error, _} ->
        {:noreply, assign(socket, sent: false, delivery_error: true)}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app {assigns} immersive>
      <div class="grid min-h-dvh lg:grid-cols-2">
        <section class="hidden flex-col justify-between border-r border-base-300 bg-peach p-12 text-peach-ink lg:flex">
          <div class="flex items-center gap-3">
            <.icon name="hero-book-open" class="size-8" />
            <span class="font-heading text-xl font-semibold">
              Open Cookbook
            </span>
          </div>
          <div class="space-y-6">
            <div class="flex size-36 items-center justify-center rounded-full border-[18px] border-base-100 bg-base-200">
              <.icon name="hero-cake" class="size-14" />
            </div>
            <h1 class="max-w-lg text-5xl leading-tight">Good food.<br />A little less fuss.</h1>
            <p class="max-w-sm text-lg leading-relaxed">
              Your favourite recipes, a plan for the week, and a calmer kitchen.
            </p>
          </div>
          <p class="text-sm">Collect. Plan. Cook. Enjoy.</p>
        </section>
        <div class="flex flex-col items-center justify-center gap-6 px-5 py-10 sm:px-10">
          <div class="flex w-full max-w-md items-center justify-between">
            <span class="font-heading text-lg font-semibold">Open Cookbook</span><button
              id="login-theme"
              phx-click={JS.dispatch("toggle-theme")}
              class="action size-11 !p-0"
              aria-label="Switch theme"
            ><.icon name="hero-sun" class="size-5 dark:hidden" /><.icon
              name="hero-moon"
              class="hidden size-5 dark:block"
            /></button>
          </div>
          <section :if={!@sent} class="surface w-full max-w-md space-y-5 p-6 sm:p-8">
            <p
              :if={@delivery_error}
              id="login-error"
              role="alert"
              class="rounded-xl bg-blush p-3 text-sm text-blush-ink"
            >
              We couldn't send your sign-in link. Please try again.
            </p>
            <p class="eyebrow">Welcome back</p>
            <h2 class="text-3xl leading-tight">Sign in to your cookbook</h2>
            <p class="text-sm leading-relaxed text-muted">
              Enter your email and we'll send you a magic link. No password to remember.
            </p>
            <.form for={@form} id="login_form" phx-submit="send_magic_link" class="space-y-4">
              <.input
                field={@form[:email]}
                type="email"
                label="Email address"
                placeholder="chef@example.com"
                autocomplete="email"
                required
                class="field"
              />
              <button
                type="submit"
                phx-disable-with="Sending…"
                class="action action-primary w-full"
              >
                Send magic link <.icon name="hero-arrow-right" class="size-5" />
              </button>
            </.form>
          </section>
          <section
            :if={@sent}
            id="login-sent"
            role="status"
            class="surface w-full max-w-md space-y-4 p-8 text-center"
          >
            <span class="mx-auto flex size-16 items-center justify-center rounded-full bg-sage text-sage-ink">
              <.icon name="hero-envelope" class="size-8" />
            </span>
            <h2 class="text-2xl">Check your inbox</h2>
            <p class="text-sm leading-relaxed text-muted">
              If this email is authorized, a magic link has been sent. The link expires in 10 minutes.
            </p>
          </section>
        </div>
      </div>
    </Layouts.app>
    """
  end
end

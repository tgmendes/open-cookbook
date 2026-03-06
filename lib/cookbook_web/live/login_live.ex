defmodule CookbookWeb.LoginLive do
  use CookbookWeb, :live_view

  alias Cookbook.Accounts
  alias Cookbook.Mailer

  import Swoosh.Email

  def mount(_params, session, socket) do
    if session["user_id"] && Accounts.get_user(session["user_id"]) do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      {:ok, assign(socket, form: to_form(%{"email" => ""}, as: :login), sent: false),
       layout: false}
    end
  end

  def handle_event("send_magic_link", %{"login" => %{"email" => email}}, socket) do
    case Accounts.get_or_create_user_by_email(email) do
      {:ok, user} ->
        {:ok, raw_token} = Accounts.create_login_token(user)
        send_magic_link_email(user, raw_token, socket)
        {:noreply, assign(socket, sent: true)}

      {:error, :unauthorized} ->
        {:noreply, assign(socket, sent: true)}
    end
  end

  defp send_magic_link_email(user, raw_token, socket) do
    magic_link = url(socket, ~p"/auth/callback?token=#{raw_token}")

    email =
      new()
      |> to(user.email)
      |> from({"Cookbook", System.get_env("MAIL_FROM", "onboarding@resend.dev")})
      |> subject("Your magic login link")
      |> text_body("Click here to log in: #{magic_link}\n\nThis link expires in 10 minutes.")
      |> html_body("""
      <h2>Login to Cookbook</h2>
      <p>Click the link below to log in:</p>
      <p><a href="#{magic_link}">Log in to Cookbook</a></p>
      <p><small>This link expires in 10 minutes.</small></p>
      """)

    Mailer.deliver(email)
  end

  def render(assigns) do
    ~H"""
    <div class="flex min-h-screen" style="font-family: 'Inter', system-ui, sans-serif; background-color: oklch(97% 0.01 80);">
      <%!-- Left panel: teal branding --%>
      <div class="hidden lg:flex lg:w-1/2 flex-col justify-between p-10 relative overflow-hidden" style="background-color: oklch(56% 0.135 180);">
        <%!-- Background decoration circles --%>
        <div class="absolute top-0 right-0 w-96 h-96 rounded-full opacity-20 -translate-y-1/3 translate-x-1/4" style="background-color: oklch(70% 0.135 175);"></div>
        <div class="absolute bottom-0 left-0 w-80 h-80 rounded-full opacity-15 translate-y-1/4 -translate-x-1/4" style="background-color: oklch(45% 0.12 180);"></div>

        <%!-- Logo --%>
        <div class="flex items-center gap-3 relative z-10">
          <div class="flex items-center justify-center w-9 h-9 rounded-xl bg-white/20 text-white">
            <.icon name="hero-book-open-solid" class="size-5" />
          </div>
          <span class="text-white font-semibold text-base">Open Cookbook</span>
        </div>

        <%!-- Hero text --%>
        <div class="relative z-10">
          <h1 class="text-5xl font-bold text-white leading-tight mb-4" style="font-family: 'Lora', Georgia, serif;">
            Your recipes,<br />beautifully<br />organized.
          </h1>
          <p class="text-white/70 text-lg leading-relaxed">
            Plan your week, cook with confidence, and let<br />AI handle the heavy lifting.
          </p>
        </div>

        <%!-- Pagination dots --%>
        <div class="flex items-center gap-2 relative z-10">
          <div class="w-6 h-2 rounded-full bg-white/80"></div>
          <div class="w-2 h-2 rounded-full bg-white/40"></div>
          <div class="w-2 h-2 rounded-full bg-white/40"></div>
        </div>
      </div>

      <%!-- Right panel: form --%>
      <div class="flex-1 flex items-center justify-center p-8" style="background-color: oklch(97% 0.01 80);">
        <div class="w-full max-w-md">
          <%!-- Mobile logo (only on small screens) --%>
          <div class="lg:hidden text-center mb-8">
            <div class="flex items-center justify-center w-14 h-14 rounded-2xl mx-auto mb-3" style="background-color: oklch(56% 0.135 180);">
              <.icon name="hero-book-open-solid" class="size-8 text-white" />
            </div>
            <h2 class="text-2xl font-bold" style="font-family: 'Lora', Georgia, serif; color: oklch(22% 0.025 180);">Open Cookbook</h2>
          </div>

          <div :if={!@sent} class="bg-white rounded-2xl p-8 shadow-sm border" style="border-color: oklch(88% 0.025 80);">
            <p class="text-xs font-semibold tracking-widest uppercase mb-2" style="color: oklch(56% 0.135 180);">Welcome back</p>
            <h2 class="text-3xl font-bold mb-2" style="font-family: 'Lora', Georgia, serif; color: oklch(22% 0.025 180);">Sign in to your cookbook</h2>
            <p class="text-sm mb-6" style="color: oklch(52% 0.015 60);">Enter your email and we'll send you a magic link — no password needed.</p>

            <.form for={@form} id="login_form" phx-submit="send_magic_link" class="space-y-4">
              <div>
                <label class="block text-sm font-medium mb-1.5" style="color: oklch(22% 0.025 180);">Email address</label>
                <input
                  type="email"
                  name="login[email]"
                  placeholder="chef@example.com"
                  required
                  class="w-full px-4 py-2.5 rounded-xl border text-sm outline-none focus:ring-2 transition-all"
                  style="border-color: oklch(88% 0.025 80); background-color: oklch(97% 0.01 80); color: oklch(22% 0.025 180); --tw-ring-color: oklch(56% 0.135 180);"
                />
              </div>
              <button
                type="submit"
                phx-disable-with="Sending..."
                class="w-full py-3 px-4 rounded-xl text-sm font-semibold text-white flex items-center justify-center gap-2 hover:opacity-90 transition-opacity"
                style="background-color: oklch(56% 0.135 180);"
              >
                Send magic link →
              </button>
            </.form>

            <p class="text-xs mt-5" style="color: oklch(52% 0.015 60);">
              By continuing you agree to our
              <a href="#" class="underline" style="color: oklch(56% 0.135 180);">terms</a>
              and
              <a href="#" class="underline" style="color: oklch(56% 0.135 180);">privacy policy</a>
            </p>
          </div>

          <div :if={@sent} class="bg-white rounded-2xl p-8 shadow-sm border text-center" style="border-color: oklch(88% 0.025 80);">
            <div class="flex items-center justify-center w-14 h-14 rounded-full mx-auto mb-4 bg-success/10">
              <.icon name="hero-check-circle-solid" class="size-8 text-success" />
            </div>
            <h2 class="text-xl font-bold mb-2" style="font-family: 'Lora', Georgia, serif; color: oklch(22% 0.025 180);">Check your inbox</h2>
            <p class="text-sm" style="color: oklch(52% 0.015 60);">
              If this email is authorized, a magic link has been sent.
              Check your inbox or
              <a href="/dev/mailbox" class="underline" style="color: oklch(56% 0.135 180);">dev mailbox</a>
              in development.
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end

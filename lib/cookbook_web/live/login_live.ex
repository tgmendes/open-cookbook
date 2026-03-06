defmodule CookbookWeb.LoginLive do
  use CookbookWeb, :live_view

  alias Cookbook.Accounts
  alias Cookbook.Mailer

  import Swoosh.Email

  def mount(_params, session, socket) do
    if session["user_id"] && Accounts.get_user(session["user_id"]) do
      {:ok, push_navigate(socket, to: ~p"/")}
    else
      {:ok, assign(socket, form: to_form(%{"email" => ""}, as: :login), sent: false)}
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
    <div class="min-h-[80vh] flex flex-col items-center justify-center">
      <div class="w-full max-w-sm">
        <%!-- Teal brand header --%>
        <div class="text-center mb-8">
          <div class="flex items-center justify-center w-16 h-16 rounded-2xl bg-gradient-to-br from-primary to-accent text-primary-content mx-auto mb-5 shadow-lg">
            <.icon name="hero-book-open-solid" class="size-9" />
          </div>
          <h1 class="text-3xl font-bold tracking-tight">Open Cookbook</h1>
          <p class="text-base-content/60 mt-2">Your personal recipe collection</p>
        </div>

        <div :if={!@sent} class="rounded-2xl border border-base-300 bg-base-200 p-7 shadow-sm">
          <p class="text-sm font-medium text-base-content/70 mb-5">Enter your email to receive a magic link</p>
          <.form for={@form} id="login_form" phx-submit="send_magic_link" class="space-y-4">
            <.input field={@form[:email]} type="email" label="Email" required />
            <.button type="submit" phx-disable-with="Sending..." class="btn btn-primary w-full">
              <.icon name="hero-paper-airplane" class="size-4 mr-1" />
              Send magic link
            </.button>
          </.form>
        </div>

        <div :if={@sent} class="rounded-2xl border border-base-300 bg-base-200 p-7 text-center shadow-sm">
          <div class="flex items-center justify-center w-12 h-12 rounded-full bg-success/10 mx-auto mb-3">
            <.icon name="hero-check-circle-solid" class="size-7 text-success" />
          </div>
          <p class="font-semibold text-lg">Check your inbox</p>
          <p class="text-base-content/60 text-sm mt-2">
            If this email is authorized, a magic link has been sent.
            Check your inbox or <a href="/dev/mailbox" class="text-primary hover:underline">dev mailbox</a> in development.
          </p>
        </div>
      </div>
    </div>
    """
  end
end

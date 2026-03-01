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
      |> from({"Cookbook", "noreply@cookbook.local"})
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
    <div class="mx-auto max-w-sm mt-20">
      <div class="text-center mb-8">
        <div class="flex items-center justify-center w-14 h-14 rounded-2xl bg-primary text-primary-content mx-auto mb-4">
          <.icon name="hero-book-open-solid" class="size-8" />
        </div>
        <h1 class="text-2xl font-bold">Log in to Cookbook</h1>
        <p class="text-base-content/60 mt-1">Enter your email to receive a magic link</p>
      </div>

      <div :if={!@sent} class="rounded-xl border border-base-200 bg-base-200 p-6">
        <.form for={@form} id="login_form" phx-submit="send_magic_link" class="space-y-4">
          <.input field={@form[:email]} type="email" label="Email" required />
          <.button type="submit" phx-disable-with="Sending..." class="btn btn-primary w-full">
            <.icon name="hero-paper-airplane" class="size-4 mr-1" />
            Send magic link
          </.button>
        </.form>
      </div>

      <div :if={@sent} class="rounded-xl border border-base-200 bg-base-200 p-6 text-center">
        <div class="flex items-center justify-center w-12 h-12 rounded-full bg-success/10 mx-auto mb-3">
          <.icon name="hero-check-circle-solid" class="size-7 text-success" />
        </div>
        <p class="font-medium">Check your inbox</p>
        <p class="text-base-content/60 text-sm mt-2">
          If this email is authorized, a magic link has been sent.
          Check your inbox or <a href="/dev/mailbox" class="text-primary hover:underline">dev mailbox</a> in development.
        </p>
      </div>
    </div>
    """
  end
end

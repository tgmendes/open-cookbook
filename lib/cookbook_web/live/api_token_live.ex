defmodule CookbookWeb.ApiTokenLive do
  use CookbookWeb, :live_view
  alias Cookbook.Accounts

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Connections",
       raw_token: nil,
       token_error: nil,
       form: to_form(%{"name" => "Claude"}, as: :token)
     )
     |> stream(:tokens, Accounts.list_api_tokens(socket.assigns.current_user)), layout: false}
  end

  def handle_event("create", %{"token" => %{"name" => name}}, socket) do
    case Accounts.create_api_token(socket.assigns.current_user, name) do
      {:ok, record, raw} ->
        {:noreply,
         socket
         |> assign(raw_token: raw, token_error: nil)
         |> stream_insert(:tokens, record, at: 0)}

      {:error, _} ->
        {:noreply,
         assign(socket,
           raw_token: nil,
           token_error: "Choose a name between 1 and 100 characters."
         )}
    end
  end

  def handle_event("dismiss", _params, socket), do: {:noreply, assign(socket, raw_token: nil)}

  def handle_event("revoke", %{"id" => id}, socket) do
    case Accounts.revoke_api_token(socket.assigns.current_user, id) do
      :ok ->
        {:noreply,
         socket
         |> assign(raw_token: nil)
         |> stream(:tokens, Accounts.list_api_tokens(socket.assigns.current_user), reset: true)}

      {:error, :not_found} ->
        {:noreply, socket |> assign(raw_token: nil) |> put_flash(:error, "Token not found.")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_user={@current_user}
      nav_path={@nav_path}
    >
      <div class="mx-auto max-w-2xl space-y-8">
        <header class="space-y-2">
          <p class="text-xs font-semibold uppercase tracking-[0.2em] text-teal-700">
            Your cookbook, connected
          </p>
          <h1 class="text-3xl font-semibold tracking-tight">Connections</h1>
          <p class="text-sm text-base-content/60">
            Give Speakeasy a private API token so Claude can save recipes and plan meals. Tokens expire after 90 days and can be revoked at any time.
          </p>
        </header>
        <section class="rounded-2xl border border-base-300/50 bg-base-100 p-6 shadow-sm">
          <.form for={@form} id="api-token-form" phx-submit="create" class="space-y-4">
            <.input field={@form[:name]} label="Connection name" required maxlength="100" />
            <p :if={@token_error} id="api-token-error" role="alert" class="text-sm text-red-700">
              {@token_error}
            </p>
            <button
              id="create-api-token"
              type="submit"
              phx-disable-with="Creating…"
              class="rounded-xl bg-teal-700 px-5 py-2.5 text-sm font-medium text-white transition-colors hover:bg-teal-800"
            >
              Create token
            </button>
          </.form>
          <div
            :if={@raw_token}
            id="new-api-token"
            class="mt-6 space-y-3 rounded-xl border border-amber-300 bg-amber-50 p-4 text-amber-950"
          >
            <p class="text-sm font-semibold">
              Copy this token now. You won't be able to retrieve it later.
            </p>
            <p class="text-sm">
              Paste it directly into Speakeasy's secure credential settings. Do not send it to Claude or put it in a chat.
            </p>
            <code
              id="api-token-secret"
              class="block select-all break-all rounded-lg bg-white p-3 text-xs"
            >
              {@raw_token}
            </code>
            <button
              id="dismiss-api-token"
              type="button"
              phx-click="dismiss"
              class="text-sm font-medium underline underline-offset-4"
            >
              I've saved it securely
            </button>
          </div>
        </section>
        <section>
          <h2 class="mb-3 text-lg font-semibold">Your API tokens</h2>
          <div id="api-tokens" phx-update="stream" class="space-y-3">
            <div
              id="no-api-tokens"
              class="hidden rounded-xl border border-dashed border-base-300 p-6 text-sm text-base-content/50 only:block"
            >
              No connections yet.
            </div>
            <div
              :for={{dom_id, token} <- @streams.tokens}
              id={dom_id}
              class="flex items-center justify-between gap-4 rounded-xl border border-base-300/50 p-4"
            >
              <div id={"api-token-#{token.id}"}>
                <p class="text-sm font-medium">{token.name}</p>
                <p class="mt-1 text-xs text-base-content/50">
                  {if token.revoked_at,
                    do: "Revoked",
                    else: "Expires #{Calendar.strftime(token.expires_at, "%d %b %Y")}"}
                </p>
              </div>
              <button
                :if={!token.revoked_at}
                id={"revoke-api-token-#{token.id}"}
                type="button"
                phx-click="revoke"
                phx-value-id={token.id}
                data-confirm="Revoke this connection? Calls using this token will stop working."
                class="rounded-lg px-3 py-2 text-sm text-red-700 transition-colors hover:bg-red-50"
              >
                Revoke
              </button>
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end

defmodule Mix.Tasks.Cookbook.Openapi do
  use Mix.Task
  @shortdoc "Export the cookbook's OpenAPI document"
  @moduledoc """
  Export the API contract to `priv/openapi.json`:

      mix cookbook.openapi --server https://open-cookbook.fly.dev

  This task does not connect to the database or deploy anything.
  """
  def run(args) do
    Mix.Task.run("compile")
    {opts, _, invalid} = OptionParser.parse(args, strict: [server: :string])
    if invalid != [], do: Mix.raise("Use --server followed by the public application URL")
    server = Keyword.get(opts, :server, "https://open-cookbook.fly.dev")
    uri = URI.parse(server)

    unless uri.scheme in ["http", "https"] and is_binary(uri.host) and is_nil(uri.userinfo) and
             is_nil(uri.query) and is_nil(uri.fragment),
           do: Mix.raise("Expected an HTTP(S) server URL without credentials, query, or fragment")

    File.write!(
      "priv/openapi.json",
      Jason.encode_to_iodata!(CookbookWeb.OpenAPI.spec(server), pretty: true)
    )

    Mix.shell().info("Exported priv/openapi.json")
  end
end

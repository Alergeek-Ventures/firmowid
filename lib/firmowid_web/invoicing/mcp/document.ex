defmodule FirmowidWeb.Invoicing.Mcp.Document do
  @moduledoc "Renders the shared MCP LiveView document without embedding company or session data."

  use Ash.Resource,
    domain: FirmowidWeb.Invoicing.Mcp,
    authorizers: [Ash.Policy.Authorizer]

  code_interface do
    define :read
  end

  actions do
    action :read, :string do
      description "Render the authenticated invoice list application shell."

      run fn _input, _context ->
        {:ok, FirmowidWeb.Mcp.Runtime.document()}
      end
    end
  end

  policies do
    policy action(:read) do
      authorize_if actor_present()
    end
  end
end

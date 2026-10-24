defmodule FirmowidWeb.Auth.Components.McpConsent do
  @moduledoc """
  Firmowid-styled consent screen for MCP OAuth authorization.

  Renders a standalone HTML document that
  loads app CSS and mirrors the login page layout. The approval names the
  organization the client will work in (see
  `FirmowidMcp.Utilities.ConsentOrganization`): a choice when the account has
  several.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button

  alias Firmowid.Ash.Core.Member
  alias Firmowid.Ash.Core.Organization

  @organizations_key {__MODULE__, :organizations}

  @doc """
  Stores the account's organizations and the preselected one for the consent
  screen rendered later in this request.

  ConsentRouter renders the view with its own assigns only, without the conn.
  """
  @spec put_organizations([Organization.t()], Member.t() | nil) :: :ok
  def put_organizations(organizations, selected) do
    Process.put(@organizations_key, {organizations, selected && selected.organization_id})
    :ok
  end

  @doc "Forgets the organizations when the request ends without rendering the screen."
  @spec delete_organizations() :: :ok
  def delete_organizations do
    Process.delete(@organizations_key)
    :ok
  end

  @doc """
  Render the consent screen as HTML iodata for ConsentRouter.
  """
  @spec render(:consent, map()) :: iodata()
  def render(:consent, assigns) do
    {organizations, selected_id} = Process.delete(@organizations_key) || {[], nil}
    assigns = Map.merge(assigns, %{organizations: organizations, selected_id: selected_id})

    Phoenix.HTML.Safe.to_iodata(~H"""
    <!DOCTYPE html>
    <html class="h-full" lang="pl">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Autoryzacja MCP · Firmowid</title>
        <link rel="icon" type="image/png" href="/images/favicon.png" />
        <link
          rel="preload"
          as="font"
          type="font/woff2"
          href="/fonts/lexend-latin.woff2"
          crossorigin
        />
        <link
          rel="preload"
          as="font"
          type="font/woff2"
          href="/fonts/lexend-latin-ext.woff2"
          crossorigin
        />
        <link rel="stylesheet" href="/assets/app.css" />
      </head>
      <body class="h-full">
        <div class="relative flex min-h-screen w-screen items-center justify-center overflow-clip px-4">
          <img
            src="/images/figurine.png"
            alt=""
            class="absolute -top-20 left-1/2 h-[135vh] opacity-10"
          />
          <div class="z-10 w-full max-w-md rounded-2xl bg-white p-8 shadow-sm ring-1 ring-grey-200">
            <h1 class="text-center text-2xl font-bold text-grey-900">
              Zezwól na dostęp
            </h1>
            <p class="mt-3 text-center text-sm text-grey-600">
              Aplikacja <span class="font-semibold text-grey-900">{@client_name}</span>
              prosi o dostęp do Twojego konta Firmowid w zakresie MCP.
            </p>

            <dl class="mt-6 space-y-3 rounded-xl bg-grey-100 p-4 text-sm text-grey-700">
              <div>
                <dt class="font-medium text-grey-900">Zakres</dt>
                <dd class="mt-0.5 font-mono text-xs break-all text-grey-600">{@scope}</dd>
              </div>
              <div>
                <dt class="font-medium text-grey-900">Zasób</dt>
                <dd class="mt-0.5 font-mono text-xs break-all text-grey-600">{@resource}</dd>
              </div>
              <div>
                <dt class="font-medium text-grey-900">Przekierowanie</dt>
                <dd class="mt-0.5 font-mono text-xs break-all text-grey-600">{@redirect_uri}</dd>
              </div>
            </dl>

            <form method="POST" action={@action_path} class="mt-6 space-y-3">
              <input type="hidden" name="_csrf_token" value={@csrf_token} />
              <input type="hidden" name="consent_request" value={@consent_request} />
              <input
                :for={organization <- @organizations}
                :if={length(@organizations) == 1}
                type="hidden"
                name="organization_id"
                value={organization.id}
              />
              <fieldset :if={length(@organizations) > 1} class="space-y-3 pb-3">
                <legend class="text-sm font-medium text-grey-900">Organizacja</legend>
                <p class="text-sm text-grey-600">
                  Aplikacja będzie działać w wybranej organizacji.
                </p>
                <label
                  :for={organization <- @organizations}
                  class="flex cursor-pointer items-center gap-2 rounded-xl bg-grey-100 p-3 text-sm text-grey-900"
                >
                  <input
                    type="radio"
                    name="organization_id"
                    value={organization.id}
                    checked={organization.id == @selected_id}
                    class="size-5 shrink-0 appearance-none rounded-full border-2 border-grey-300 bg-white checked:bg-teal-700 focus:outline-none"
                  />
                  <span class="font-medium">{organization.name}</span>
                </label>
              </fieldset>
              <.button variant="special" type="submit" name="action" value="approve" class="w-full">
                Zezwól
              </.button>
              <.button variant="outline" type="submit" name="action" value="deny" class="w-full">
                Odrzuć
              </.button>
            </form>
          </div>
        </div>
      </body>
    </html>
    """)
  end
end

defmodule FirmowidWeb.Auth.Components.McpConsent do
  @moduledoc """
  Firmowid-styled consent screen for MCP OAuth authorization.

  Renders a standalone HTML document that
  loads app CSS and mirrors the login page layout.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button

  @doc """
  Render the consent screen as HTML iodata for ConsentRouter.
  """
  @spec render(:consent, map()) :: iodata()
  def render(:consent, assigns) do
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

            <dl class="mt-6 space-y-3 rounded-xl bg-lightGreyBg p-4 text-sm text-grey-700">
              <div>
                <dt class="font-medium text-grey-900">Zakres</dt>
                <dd class="font-mono mt-0.5 text-xs break-all text-grey-600">{@scope}</dd>
              </div>
              <div>
                <dt class="font-medium text-grey-900">Zasób</dt>
                <dd class="font-mono mt-0.5 text-xs break-all text-grey-600">{@resource}</dd>
              </div>
              <div>
                <dt class="font-medium text-grey-900">Przekierowanie</dt>
                <dd class="font-mono mt-0.5 text-xs break-all text-grey-600">{@redirect_uri}</dd>
              </div>
            </dl>

            <form method="POST" action={@action_path} class="mt-6 space-y-3">
              <input type="hidden" name="_csrf_token" value={@csrf_token} />
              <input type="hidden" name="consent_request" value={@consent_request} />
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

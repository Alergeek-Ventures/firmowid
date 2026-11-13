defmodule FirmowidWeb.Auth.Components.McpConsent do
  @moduledoc """
  Firmowid-styled consent screen for MCP OAuth authorization.

  Renders a standalone HTML document that
  loads app CSS and mirrors the login page layout. The approval names the
  organization the client will work in (see
  `FirmowidWeb.Auth.Utilities.ConsentOrganization`): a choice when the account has
  several.
  """

  use FirmowidWeb, :html

  import FirmowidUI.Components.Button

  alias Firmowid.Core.Member
  alias Firmowid.Core.Organization

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
    <html class="h-full" lang={Gettext.get_locale(Firmowid.Gettext)}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{gettext("MCP authorization")} · Firmowid</title>
        <link rel="icon" type="image/png" href="/images/favicon.png" />
        <link
          rel="preload"
          as="font"
          type="font/woff2"
          href="/fonts/geist-latin.woff2"
          crossorigin
        />
        <link
          rel="preload"
          as="font"
          type="font/woff2"
          href="/fonts/geist-latin-ext.woff2"
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
            <h1 class="text-center text-2xl font-bold text-balance wrap-break-word text-grey-900">
              {gettext("Connect %{client} to Firmowid?", client: @client_name)}
            </h1>
            <form method="POST" action={@action_path}>
              <input type="hidden" name="_csrf_token" value={@csrf_token} />
              <input type="hidden" name="consent_request" value={@consent_request} />
              <.company
                client_name={@client_name}
                organizations={@organizations}
                selected_id={@selected_id}
              />
              <%!-- What the MCP tools (Firmowid.AiTools.mcp/0) can do, in plain words. --%>
              <ul class="mbs-7 grid gap-3.5 text-sm text-grey-900">
                <.permission text={
                  gettext(
                    "Reads the company's invoices, clients, transfers, salaries, working time and leave"
                  )
                }>
                  <Lucideicons.eye class="size-4.5" />
                </.permission>
                <.permission text={
                  gettext(
                    "Records working time and leave, adds notes and categories, and matches transfers with invoices and salaries"
                  )
                }>
                  <Lucideicons.pencil_line class="size-4.5" />
                </.permission>
                <.permission text={
                  gettext("Changes your profile, including the bank account for your pay")
                }>
                  <Lucideicons.user_round_pen class="size-4.5" />
                </.permission>
                <.permission text={
                  gettext("Saves invoice drafts, which go to KSeF only after you confirm them")
                }>
                  <Lucideicons.file_check class="size-4.5" />
                </.permission>
                <.permission
                  text={gettext("Never gets your KSeF or bank login details")}
                  class="border-bs border-grey-200 pbs-3.5"
                >
                  <Lucideicons.lock class="size-4.5" />
                </.permission>
              </ul>
              <div class="mbs-8 grid gap-3">
                <.button variant="special" type="submit" name="action" value="approve" class="w-full">
                  {gettext("Allow")}
                </.button>
                <.button variant="outline" type="submit" name="action" value="deny" class="w-full">
                  {gettext("Deny")}
                </.button>
              </div>
            </form>
            <p class="mbs-5 text-center text-xs text-grey-600">
              {gettext("After your decision you will return to %{host}.",
                host: redirect_host(@redirect_uri)
              )}
            </p>
            <%!-- The request as the OAuth server sees it, for those who compare addresses. --%>
            <details class="mbs-2 text-center text-xs text-grey-600">
              <summary class="cursor-pointer underline underline-offset-4">
                {gettext("Technical details")}
              </summary>
              <dl class="mbs-3 grid gap-2 text-start [&_dd]:font-mono [&_dd]:break-all [&_dt]:font-medium [&_dt]:text-grey-900">
                <div>
                  <dt>{gettext("Scope")}</dt>
                  <dd>{@scope}</dd>
                </div>
                <div>
                  <dt>{gettext("Resource")}</dt>
                  <dd>{@resource}</dd>
                </div>
                <div>
                  <dt>{gettext("Redirect")}</dt>
                  <dd>{@redirect_uri}</dd>
                </div>
              </dl>
            </details>
          </div>
        </div>
      </body>
    </html>
    """)
  end

  attr :client_name, :string, required: true
  attr :organizations, :list, required: true
  attr :selected_id, :string, required: true

  # One company is named; with several the person picks, in plain rows rather than boxes.
  defp company(%{organizations: [organization]} = assigns) do
    assigns = assign(assigns, :organization, organization)

    ~H"""
    <input type="hidden" name="organization_id" value={@organization.id} />
    <p class="mbs-3 text-center text-sm text-grey-600">
      {gettext("Company")}
      <span class="font-medium text-grey-900">{@organization.display_name}</span>
    </p>
    """
  end

  defp company(assigns) do
    ~H"""
    <%!-- The extra space keeps the choice apart from the permissions under it. --%>
    <fieldset class="mbs-3 mbe-2">
      <legend class="mx-auto text-center text-sm text-grey-600">
        {gettext("Choose the company %{client} will work in.", client: @client_name)}
      </legend>
      <div class="mbs-3 grid gap-2.5">
        <label
          :for={organization <- @organizations}
          class="flex cursor-pointer items-center gap-2.5 text-sm font-medium text-grey-900"
        >
          <input
            type="radio"
            name="organization_id"
            value={organization.id}
            checked={organization.id == @selected_id}
            class="size-4.5 shrink-0 appearance-none rounded-full border-2 border-grey-300 bg-white checked:border-5 checked:border-grey-900 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-black"
          />
          {organization.display_name}
        </label>
      </div>
    </fieldset>
    """
  end

  attr :text, :string, required: true
  attr :class, :any, default: nil
  slot :inner_block, required: true, doc: "the icon"

  defp permission(assigns) do
    ~H"""
    <li class={["flex items-start gap-3", @class]}>
      <span class="mbs-px text-grey-500" aria-hidden="true">{render_slot(@inner_block)}</span>
      {@text}
    </li>
    """
  end

  # The host is what a person can check. NormalizeRedirectUri admits only addresses with one.
  defp redirect_host(redirect_uri), do: URI.parse(redirect_uri).host
end

defmodule FirmowidWeb.Settings.Components.McpIntegration do
  @moduledoc """
  The AI assistants subpage of the "Integrations" settings page: how to connect ChatGPT, Claude,
  Cursor and other MCP clients to Firmowid's MCP server. A client signs in with the person's
  Firmowid account and works in the company chosen on the consent screen, so the page only
  explains the steps; there is nothing to set up here.
  """
  use FirmowidWeb, :html

  import FirmowidUI.Components.Button
  import FirmowidUI.Components.Link
  import FirmowidWeb.Auth.Components.ClientLogo, only: [client_logo: 1]
  import FirmowidWeb.Settings.Components.Integrations, only: [integration_step: 1]
  import Phoenix.Component, except: [link: 1]

  alias Phoenix.LiveView.Rendered

  # The Firmowid plugin in the ChatGPT plugin directory, where the person installs it.
  @chatgpt_app_url "https://chatgpt.com/plugins/plugin_asdk_app_6ad767e3962081918299eef00fc0533a"

  @doc "Renders the MCP connection steps with the server address to copy."
  @spec mcp_integration(map()) :: Rendered.t()
  attr :mcp_url, :string, required: true

  def mcp_integration(assigns) do
    assigns = assign(assigns, :chatgpt_app_url, @chatgpt_app_url)

    ~H"""
    <section
      id="mcp-integration"
      class="grid items-start gap-x-12 gap-y-10 lg:grid-cols-[minmax(0,1fr)_22rem]"
    >
      <div class="flex max-w-xl flex-col gap-8">
        <ol class="space-y-8">
          <.integration_step number={1} content_class="mbs-3">
            <:title>{gettext("Add Firmowid to your assistant")}</:title>
            <:content>
              <ul class="divide-y divide-grey-200 border-y border-grey-200">
                <li class="flex flex-wrap items-center gap-x-4 gap-y-3 py-4">
                  <.client_logo app={:chatgpt} class="size-9 rounded-md p-2" />
                  <span class="flex min-w-40 flex-1 flex-col">
                    <span class="font-medium text-grey-900">ChatGPT</span>
                    <span>{gettext("Install the Firmowid plugin there")}</span>
                  </span>
                  <.link
                    kind="button"
                    variant="special"
                    size="small"
                    external={@chatgpt_app_url}
                    target="_blank"
                    rel="noopener noreferrer"
                  >
                    {gettext("Add to ChatGPT")}
                    <Lucideicons.arrow_up_right class="size-4" aria-hidden="true" />
                  </.link>
                </li>
                <li class="flex flex-col gap-3 py-4">
                  <span class="flex items-center gap-4">
                    <.client_logo app={:claude} class="size-9 rounded-md p-2" />
                    <span class="flex flex-col">
                      <span class="font-medium text-grey-900">
                        {gettext("Claude, Cursor and other programs")}
                      </span>
                      <span>{gettext("Add this MCP server; in Claude it is a custom connector")}</span>
                    </span>
                  </span>
                  <span class="flex items-center gap-2 sm:ps-13">
                    <input
                      id="mcp-url"
                      type="text"
                      readonly
                      value={@mcp_url}
                      title={@mcp_url}
                      aria-label={gettext("MCP server address")}
                      class="h-7.5 min-w-0 flex-1 truncate rounded-sm border border-grey-200 bg-grey-50 px-3 font-mono text-sm text-grey-900"
                    />
                    <.button
                      id="copy-mcp-url"
                      type="button"
                      variant="tertiary"
                      size="small"
                      phx-hook="CopyToClipboard"
                      data-copy-text={@mcp_url}
                    >
                      <.figma_icon name="copy" class="size-4" />
                      <span data-copy-label>{gettext("Copy")}</span>
                      <span data-copy-done class="hidden">{gettext("Copied")}</span>
                    </.button>
                  </span>
                </li>
              </ul>
            </:content>
          </.integration_step>
          <.integration_step number={2}>
            <:title>{gettext("Sign in with your Firmowid account")}</:title>
          </.integration_step>
          <.integration_step number={3}>
            <:title>{gettext("Choose the company")}</:title>
            <:content>
              {gettext(
                "On the consent screen. The assistant works only in that company and can do what your role allows."
              )}
            </:content>
          </.integration_step>
        </ol>

        <p class="flex flex-wrap items-center gap-x-4 gap-y-2">
          <.link kind="text" size="small" navigate={~p"/funkcje/claude-chatgpt-mcp"}>
            {gettext("How it works")}
          </.link>
          <.link kind="text" size="small" navigate={~p"/pomoc/narzedzia-mcp"}>
            {gettext("List of MCP tools")}
          </.link>
        </p>
      </div>

      <.example_conversation />
    </section>
    """
  end

  # What working with the assistant looks like: a request, the answer and the invoice preview the
  # person confirms before anything goes to KSeF. The data is made up.
  defp example_conversation(assigns) do
    ~H"""
    <aside
      aria-label={gettext("Example")}
      class="flex flex-col gap-4 lg:border-l lg:border-grey-200 lg:ps-12"
    >
      <h2 class="text-h5 font-medium text-grey-900">{gettext("For example")}</h2>
      <p class="max-w-[85%] self-end rounded-md bg-grey-100 px-3 py-2 text-sm/snug text-grey-900">
        {gettext("Issue an invoice to Acme Sp. z o.o. for the rollout, 1,230 PLN net")}
      </p>
      <p class="text-sm/snug text-grey-700">
        {gettext("I have prepared the invoice. Check it and confirm, and it goes to KSeF.")}
      </p>
      <div class="flex flex-col gap-3 rounded-md border border-grey-200 bg-white p-4">
        <div class="flex items-center justify-between gap-2">
          <span class="text-sm font-medium text-grey-900">{gettext("Sales invoice")}</span>
          <.badge tone="sales">{gettext("Preview")}</.badge>
        </div>
        <dl class="grid grid-cols-[auto_minmax(0,1fr)] gap-x-4 gap-y-1 text-sm">
          <dt class="text-grey-600">{gettext("Buyer")}</dt>
          <dd class="truncate text-end text-grey-900">Acme Sp. z o.o.</dd>
          <dt class="text-grey-600">{gettext("Net")}</dt>
          <dd class="text-end text-grey-900 tabular-nums">1 230,00 zł</dd>
          <dt class="text-grey-600">{gettext("Gross")}</dt>
          <dd class="text-end font-semibold text-grey-900 tabular-nums">1 512,90 zł</dd>
        </dl>
        <span
          class="inline-flex h-7.5 items-center justify-center rounded-sm bg-teal-700 px-2 text-sm font-medium text-white"
          aria-hidden="true"
        >
          {gettext("Issue and send to KSeF")}
        </span>
      </div>
    </aside>
    """
  end
end

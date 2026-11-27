defmodule FirmowidWeb.Settings.Components.Integrations do
  @moduledoc """
  The "Integrations" settings page: a catalog of integrations, each a tile leading to its own
  subpage (see `FirmowidWeb.Settings.Utilities.Navigation.integration_path/1`), and the pieces
  the subpages share: the logo of an integration and a numbered setup step.
  """
  use FirmowidWeb, :html

  import FirmowidUI.Components.Link
  import FirmowidWeb.Auth.Components.ClientLogo, only: [client_logo: 1]
  import Phoenix.Component, except: [link: 1]

  alias FirmowidWeb.Settings.Utilities.Navigation
  alias Phoenix.LiveView.Rendered

  @doc "Renders the catalog of the integrations the member may set up, each leading to its subpage."
  @spec integrations_index(map()) :: Rendered.t()
  attr :integrations, :list, required: true
  attr :api_key_count, :integer, required: true

  def integrations_index(assigns) do
    ~H"""
    <ul
      id="integrations"
      class="grid grid-cols-[repeat(auto-fill,minmax(min(100%,19rem),1fr))] gap-4"
    >
      <li :for={integration <- @integrations} class="flex">
        <.link
          kind="unstyled"
          patch={Navigation.integration_path(integration)}
          class="group flex flex-1 flex-col rounded-md border border-grey-200 bg-white p-5 transition-colors duration-100 hover:border-grey-500 motion-reduce:transition-none"
        >
          <span class="flex items-start justify-between gap-3">
            <.integration_logo integration={integration} />
            <.badge :if={integration == :api and @api_key_count > 0}>
              {ngettext("%{count} key", "%{count} keys", @api_key_count)}
            </.badge>
          </span>
          <span class="mbs-4 text-lg font-semibold text-grey-900">
            {Navigation.integration_title(integration)}
          </span>
          <span class="mbs-1 flex-1 text-sm/snug text-grey-700">{description(integration)}</span>
          <.integration_preview integration={integration} />
          <span class="mbs-5 flex items-center gap-1 border-t border-grey-200 pbs-4 text-sm font-medium text-grey-900">
            {call_to_action(integration)}
            <.figma_icon
              name="chevron_right"
              class="size-4 transition-transform duration-100 group-hover:translate-x-0.5 motion-reduce:transition-none"
            />
          </span>
        </.link>
      </li>
    </ul>
    """
  end

  attr :integration, :atom, required: true

  # What each integration does, shown with the things it works with rather than described again.
  defp integration_preview(%{integration: :mcp} = assigns) do
    ~H"""
    <span class="mbs-5 flex items-center gap-2 text-xs text-grey-600">
      <span class="flex -space-x-1" aria-hidden="true">
        <.client_logo app={:chatgpt} class="size-6 rounded-full p-1 ring-2 ring-white" />
        <.client_logo app={:claude} class="size-6 rounded-full p-1 ring-2 ring-white" />
        <.client_logo app={:mcp} class="size-6 rounded-full p-1 ring-2 ring-white" />
      </span>
      {gettext("ChatGPT, Claude and others")}
    </span>
    """
  end

  defp integration_preview(%{integration: :api} = assigns) do
    ~H"""
    <span class="mbs-5 truncate font-mono text-xs text-grey-600">
      POST /api/v1/list_sales_invoices
    </span>
    """
  end

  @doc "Renders the logo of an integration, on its tile and in its subpage's header."
  @spec integration_logo(map()) :: Rendered.t()
  attr :integration, :atom, required: true

  # The MCP mark stands for every AI assistant.
  def integration_logo(%{integration: :mcp} = assigns) do
    ~H"""
    <.client_logo app={:mcp} class="size-12 rounded-md p-2.5" />
    """
  end

  def integration_logo(%{integration: :api} = assigns) do
    ~H"""
    <span
      class="grid size-12 shrink-0 place-items-center rounded-md bg-black p-2.5 text-white"
      aria-hidden="true"
    >
      <Lucideicons.code_xml class="size-full" />
    </span>
    """
  end

  @doc """
  Renders a numbered step of an integration's setup inside an `<ol>`, laid out like the steps of
  the KSeF connection (`FirmowidUI.Components.KsefConnection`) but in black: an integration is
  neither a cost nor a sale.
  """
  @spec integration_step(map()) :: Rendered.t()
  attr :number, :integer, required: true
  attr :content_class, :string, default: nil
  slot :title, required: true
  slot :content

  def integration_step(assigns) do
    ~H"""
    <li class="grid grid-cols-[min-content_minmax(0,1fr)] items-center gap-x-3">
      <span class="flex size-7 shrink-0 items-center justify-center rounded-full bg-black text-sm font-semibold text-white">
        {@number}
      </span>
      <div class="text-base font-medium text-grey-900">{render_slot(@title)}</div>
      <div
        :for={content <- @content}
        class={["col-start-2 mbs-1 text-sm/snug text-grey-700", @content_class]}
      >
        {render_slot(content)}
      </div>
    </li>
    """
  end

  @doc "Describes an integration in one line, on its tile and under its subpage's title."
  @spec description(Navigation.integration()) :: String.t()
  def description(:mcp),
    do: gettext("ChatGPT, Claude, Cursor and other programs that support MCP work on your company's data")

  def description(:api), do: gettext("Keys your own programs, such as an online store, use to call Firmowid")

  defp call_to_action(:mcp), do: gettext("Connect an assistant")
  defp call_to_action(:api), do: gettext("Manage keys")
end

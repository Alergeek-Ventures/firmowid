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
  defp integration_preview(%{integration: :stripe} = assigns) do
    ~H"""
    <span class="mbs-5 flex flex-wrap items-center gap-1.5" aria-hidden="true">
      <.badge>{gettext("Payment")}</.badge>
      <Lucideicons.arrow_right class="size-3.5 text-grey-500" />
      <.badge tone="sales">{gettext("Invoice")}</.badge>
      <Lucideicons.arrow_right class="size-3.5 text-grey-500" />
      <.badge tone="success">KSeF</.badge>
    </span>
    """
  end

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

  # The MCP mark stands for every AI assistant; the Stripe mark comes from Simple Icons (CC0),
  # like the client logos, and the name stays with its owner.
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

  def integration_logo(%{integration: :stripe} = assigns) do
    ~H"""
    <span
      class="grid size-12 shrink-0 place-items-center rounded-md bg-[#635bff] p-2.5 text-white"
      aria-hidden="true"
    >
      <svg viewBox="0 0 24 24" fill="currentColor" class="size-full">
        <path d="M13.976 9.15c-2.172-.806-3.356-1.426-3.356-2.409 0-.831.683-1.305 1.901-1.305 2.227 0 4.515.858 6.09 1.631l.89-5.494C18.252.975 15.697 0 12.165 0 9.667 0 7.589.654 6.104 1.872 4.56 3.147 3.757 4.992 3.757 7.218c0 4.039 2.467 5.76 6.476 7.219 2.585.92 3.445 1.574 3.445 2.583 0 .98-.84 1.545-2.354 1.545-1.875 0-4.965-.921-6.99-2.109l-.9 5.555C5.175 22.99 8.385 24 11.714 24c2.641 0 4.843-.624 6.328-1.813 1.664-1.305 2.525-3.236 2.525-5.732 0-4.128-2.524-5.851-6.594-7.305h.003z" />
      </svg>
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

  def description(:stripe), do: gettext("Payments in Stripe become invoices on their own and go to KSeF")

  defp call_to_action(:mcp), do: gettext("Connect an assistant")
  defp call_to_action(:api), do: gettext("Manage keys")
  defp call_to_action(:stripe), do: gettext("Connect Stripe")
end

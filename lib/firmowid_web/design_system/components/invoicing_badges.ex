defmodule FirmowidWeb.DesignSystem.Components.InvoicingBadges do
  @moduledoc """
  App-owned invoicing badges for the design system.

  The bank badge variants are implemented from the Figma component set at
  node `11701:17853` using the exported asset slices, so the rendered result
  matches the source design while the public API stays centralized here.
  """

  use FirmowidWeb, :html

  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.SalesInvoice
  alias FirmowidUI.Components.InvoiceSourceBadge
  alias FirmowidWeb.DesignSystem.Components.InvoicingBadgeSpecs
  alias FirmowidWeb.Invoicing.Utilities.BankBadges
  alias Phoenix.LiveView.Rendered

  @bank_sizes ["full", "mini"]
  @invoice_source_variants ["cost_external", "cost_ksef", "sales", "sales_draft", "sales_ksef"]
  @invoice_source_sizes ["small", "big"]

  @doc """
  Returns all supported bank badge variants in preview order.
  """
  @spec bank_badge_variants() :: [String.t()]
  def bank_badge_variants, do: InvoicingBadgeSpecs.bank_badge_variants()

  @doc """
  Renders a Figma-faithful bank badge.

  Input may be a badge name directly (`:bank`) or a GoCardless institution
  struct/map (`:institution`) / institution id (`:institution_id`).
  The input is normalized to one of supported badge variants, with a safe
  fallback to `"Default"`.
  """
  @spec bank_badge(map()) :: Rendered.t()
  attr :bank, :string,
    default: nil,
    doc: "Bank name or explicit badge variant candidate."

  attr :institution, :any,
    default: nil,
    doc: "GoCardless institution struct/map used for resolution."

  attr :institution_id, :string,
    default: nil,
    doc: "GoCardless institution id used for resolution."

  attr :size, :string,
    default: "full",
    values: @bank_sizes,
    doc: "Figma-aligned size modifier."

  attr :class, :any, default: nil, doc: "Additional classes merged into the badge root."

  attr :rest, :global, include: ~w(aria-label title phx-click phx-hook id data-test-id)

  def bank_badge(assigns) do
    bank = resolve_bank_badge(assigns)
    spec = InvoicingBadgeSpecs.fetch_bank_badge_spec!(bank, assigns.size)

    assigns =
      assigns
      |> assign(:bank, bank)
      |> assign(:spec, spec)

    ~H"""
    <.bank_shell
      size={@size}
      bg={@spec.bg}
      indicator={@spec.indicator}
      root={Map.get(@spec, :root)}
      bank={@bank}
      class={@class}
      rest={@rest}
    >
      {render_logo(@spec.logo)}
    </.bank_shell>
    """
  end

  @doc """
  Renders an invoice source badge.
  """
  @spec invoice_source_badge(map()) :: Rendered.t()
  attr :variant, :string,
    required: true,
    values: @invoice_source_variants,
    doc: "Visual invoice badge variant."

  attr :size, :string,
    required: true,
    values: @invoice_source_sizes,
    doc: "Size modifier for compact table and larger header contexts."

  attr :class, :any, default: nil, doc: "Additional classes merged into the badge root."

  attr :rest, :global, include: ~w(aria-label title phx-click phx-hook id data-test-id)

  def invoice_source_badge(assigns), do: InvoiceSourceBadge.invoice_source_badge(assigns)

  @doc """
  Resolves the invoice badge variant for a cost or sales invoice.
  """
  @spec invoice_source_badge_variant(CostInvoice.t() | SalesInvoice.t()) :: String.t()
  def invoice_source_badge_variant(%CostInvoice{ksef_number: ksef_number}) when is_binary(ksef_number), do: "cost_ksef"

  def invoice_source_badge_variant(%CostInvoice{ksef_downloaded_at: downloaded_at}) when not is_nil(downloaded_at),
    do: "cost_ksef"

  def invoice_source_badge_variant(%CostInvoice{ksef_permanent_storage_date: storage_date}) when not is_nil(storage_date),
    do: "cost_ksef"

  def invoice_source_badge_variant(%CostInvoice{}), do: "cost_external"

  def invoice_source_badge_variant(%SalesInvoice{ksef_number: ksef_number}) when is_binary(ksef_number), do: "sales_ksef"

  def invoice_source_badge_variant(%SalesInvoice{ksef_session_reference_number: reference}) when is_binary(reference),
    do: "sales_ksef"

  def invoice_source_badge_variant(%SalesInvoice{invoice_number: nil}), do: "sales_draft"

  def invoice_source_badge_variant(%SalesInvoice{}), do: "sales"

  @doc """
  Returns the human-readable label for an invoice badge variant.
  """
  @spec invoice_source_badge_label(String.t()) :: String.t()
  def invoice_source_badge_label("cost_external"), do: gettext("Invoice from outside KSeF")

  def invoice_source_badge_label("cost_ksef"), do: gettext("Invoice from the National e-Invoice System")

  def invoice_source_badge_label("sales"), do: gettext("Invoice issued in Firmowid")
  def invoice_source_badge_label("sales_draft"), do: gettext("Draft being issued in Firmowid")

  def invoice_source_badge_label("sales_ksef"), do: gettext("Invoice from the National e-Invoice System")

  def invoice_source_badge_label(_variant), do: "—"

  defp resolve_bank_badge(assigns) do
    cond do
      assigns[:institution] not in [nil] ->
        BankBadges.badge_for_institution(assigns[:institution])

      is_binary(assigns[:institution_id]) ->
        BankBadges.badge_for_institution(assigns[:institution_id])

      InvoicingBadgeSpecs.supported_bank_variant?(assigns[:bank]) ->
        assigns[:bank]

      is_binary(assigns[:bank]) ->
        BankBadges.badge_for(assigns[:bank])

      true ->
        "Default"
    end
  end

  attr :size, :string, required: true, values: @bank_sizes
  attr :bg, :string, required: true
  attr :indicator, :string, default: nil
  attr :bank, :string, required: true
  attr :root, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :any, default: %{}
  slot :inner_block, required: true

  defp bank_shell(assigns) do
    resolved_root_class =
      cond do
        assigns.size == "full" ->
          "relative flex h-[42px] w-[72px] content-stretch items-center gap-[16px] rounded-[4px] pr-[4px] pl-[8px]"

        is_binary(assigns.root) ->
          assigns.root

        true ->
          "relative flex h-[24px] w-[36px] content-stretch items-center justify-center rounded-[2px]"
      end

    assigns = assign(assigns, :resolved_root_class, resolved_root_class)

    ~H"""
    <div
      class={[@resolved_root_class, @bg, @class]}
      data-bank={@bank}
      data-size={@size}
      {@rest}
    >
      <span class="sr-only">{@bank}</span>
      {render_slot(@inner_block)}
      <div
        :if={@size == "full" and @indicator}
        class="absolute top-[28px] left-[51.5px] h-[10px] w-[16.5px]"
      >
        <img alt="" class="absolute inset-0 block size-full max-w-none" src={asset(@indicator)} />
      </div>
    </div>
    """
  end

  # sobelow_skip ["XSS.Raw"]
  # The logo tree is fixed badge metadata shipped with the app (tags, attrs and
  # local asset paths), not request input; attribute values are still escaped.
  defp render_logo(logo), do: Phoenix.HTML.raw(render_logo_iodata(logo))

  defp render_logo_iodata(%{tag: :img, attrs: attrs, asset: asset_name}) do
    ["<img", render_attrs(Keyword.put(attrs, :src, asset(asset_name))), ">"]
  end

  defp render_logo_iodata(%{tag: tag, attrs: attrs, children: children}) do
    [
      "<",
      Atom.to_string(tag),
      render_attrs(attrs),
      ">",
      Enum.map(children, &render_logo_iodata/1),
      "</",
      Atom.to_string(tag),
      ">"
    ]
  end

  defp render_attrs(attrs), do: Enum.map(attrs, &render_attr/1)

  defp render_attr({name, value}) do
    escaped_value =
      value
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()

    [" ", Atom.to_string(name), "=\"", escaped_value, "\""]
  end

  defp asset(filename), do: "/images/invoicing_badges/#{filename}"
end

defmodule FirmowidWeb.DesignSystem.Components.InvoicingBadges do
  @moduledoc """
  App-owned invoicing badges for the design system.

  The bank badge variants are implemented from the Figma component set at
  node `11701:17853` using the exported asset slices, so the rendered result
  matches the source design while the public API stays centralized here.
  """

  use FirmowidWeb, :html

  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias FirmowidWeb.DesignSystem.Components.InvoicingBadgeSpecs
  alias FirmowidWeb.DesignSystem.Components.InvoicingBankBadge
  alias FirmowidWeb.DesignSystem.Components.InvoicingInvoiceSourceBadge
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

  def bank_badge(assigns), do: InvoicingBankBadge.bank_badge(assigns)

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

  def invoice_source_badge(assigns), do: InvoicingInvoiceSourceBadge.invoice_source_badge(assigns)

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
  def invoice_source_badge_label("cost_external"), do: "Faktura spoza KSeF"
  def invoice_source_badge_label("cost_ksef"), do: "Faktura z Krajowego Systemu e-Faktur"
  def invoice_source_badge_label("sales"), do: "Faktura wystawiona w Firmowidzie"
  def invoice_source_badge_label("sales_draft"), do: "Szkic wystawiany w Firmowidzie"
  def invoice_source_badge_label("sales_ksef"), do: "Faktura z Krajowego Systemu e-Faktur"
  def invoice_source_badge_label(_variant), do: "—"
end

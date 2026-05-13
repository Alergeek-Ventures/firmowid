defmodule FirmowidWeb.DesignSystem.Components.InvoicingInvoiceSourceBadge do
  @moduledoc """
  Invoice source badge implementation for the design system.
  """

  use FirmowidWeb, :html

  alias Phoenix.LiveView.Rendered

  @doc """
  Renders an invoice source badge.
  """
  @spec invoice_source_badge(map()) :: Rendered.t()
  def invoice_source_badge(assigns) do
    assigns =
      assigns
      |> assign_new(:class, fn -> nil end)
      |> assign_new(:rest, fn -> %{} end)

    ~H"""
    <div
      class={[
        "relative inline-flex shrink-0 items-center justify-center",
        @size == "small" && "h-6 w-9 rounded-[2.286px]",
        @size == "big" && "h-8 w-12 rounded-[3px]",
        @variant == "cost_external" && "bg-orangeBg",
        @variant == "cost_ksef" && "bg-orangeBg",
        @variant == "sales" && "bg-blueBg",
        @variant == "sales_draft" && "bg-blueBg",
        @variant == "sales_ksef" && "bg-turquoise-200",
        @class
      ]}
      data-size={@size}
      data-variant={@variant}
      {@rest}
    >
      <span class="sr-only">
        {case @variant do
          "cost_external" -> "Faktura spoza KSeF"
          "cost_ksef" -> "Faktura z Krajowego Systemu e-Faktur"
          "sales" -> "Faktura wystawiona w Firmowidzie"
          "sales_draft" -> "Szkic wystawiany w Firmowidzie"
          "sales_ksef" -> "Faktura z Krajowego Systemu e-Faktur"
        end}
      </span>
      <Lucideicons.file_input
        :if={@variant == "cost_external"}
        class={[if(@size == "small", do: "text-orangeText size-4", else: "text-orangeText size-5")]}
      />
      <Lucideicons.file_pen_line
        :if={@variant in ["sales", "sales_draft"]}
        class={[if(@size == "small", do: "text-blueText size-4", else: "text-blueText size-5")]}
      />
      <span
        :if={@variant in ["cost_ksef", "sales_ksef"]}
        class={[
          @size == "small" && "text-[10px] leading-[1.55] font-semibold tracking-tight",
          @size == "big" && "text-xs leading-[1.4] font-semibold tracking-tight",
          @variant == "cost_ksef" && "text-[#013066]",
          @variant == "sales_ksef" && "text-black"
        ]}
      >
        KS<span class="text-[#e70012]">e</span>F
      </span>
    </div>
    """
  end
end

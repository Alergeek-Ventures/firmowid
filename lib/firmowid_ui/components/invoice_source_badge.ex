defmodule FirmowidUI.Components.InvoiceSourceBadge do
  @moduledoc """
  Invoice source badge implementation for the design system.
  """

  use FirmowidUI, :html

  alias Phoenix.LiveView.Rendered

  @doc """
  Renders an invoice source badge.
  """
  @spec invoice_source_badge(map()) :: Rendered.t()
  attr :variant, :string,
    required: true,
    values: ["cost_external", "cost_ksef", "sales", "sales_draft", "sales_ksef"],
    doc: "Visual invoice badge variant."

  attr :size, :string,
    required: true,
    values: ["small", "big"],
    doc: "Size modifier for compact table and larger header contexts."

  attr :class, :any, default: nil, doc: "Additional classes merged into the badge root."
  attr :rest, :global, include: ~w(aria-label title phx-click phx-hook id data-test-id)

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
        @variant == "cost_external" && "bg-rust-200",
        @variant == "cost_ksef" && "bg-rust-200",
        @variant == "sales" && "bg-teal-200",
        @variant == "sales_draft" && "bg-teal-200",
        @variant == "sales_ksef" && "bg-teal-200",
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
        class={[if(@size == "small", do: "size-4 text-rust-700", else: "size-5 text-rust-700")]}
      />
      <Lucideicons.file_pen_line
        :if={@variant in ["sales", "sales_draft"]}
        class={[if(@size == "small", do: "size-4 text-teal-800", else: "size-5 text-teal-800")]}
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

defmodule FirmowidWeb.DesignSystem.Components.InvoicingBankBadge do
  @moduledoc """
  Bank badge implementation for the design system.
  """

  use FirmowidWeb, :html

  alias FirmowidWeb.DesignSystem.Components.InvoicingBadgeSpecs
  alias FirmowidWeb.Invoicing.Utilities.BankBadges
  alias Phoenix.LiveView.Rendered

  @sizes ["full", "mini"]

  @doc """
  Renders a Figma-faithful bank badge from the internal badge specs.
  """
  @spec bank_badge(map()) :: Rendered.t()
  def bank_badge(assigns) do
    assigns =
      assigns
      |> assign_new(:bank, fn -> nil end)
      |> assign_new(:institution, fn -> nil end)
      |> assign_new(:institution_id, fn -> nil end)
      |> assign_new(:size, fn -> "full" end)
      |> assign_new(:class, fn -> nil end)
      |> assign_new(:rest, fn -> %{} end)

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

  attr :size, :string, required: true, values: @sizes
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
  # This <img> tag is assembled from static badge metadata and local asset paths
  # defined in this module, not from any user-controlled input.
  defp render_logo(%{tag: :img, attrs: attrs, asset: asset_name}) do
    Phoenix.HTML.raw(["<img", render_attrs(Keyword.put(attrs, :src, asset(asset_name))), ">"])
  end

  # sobelow_skip ["XSS.Raw"]
  # SVG/logo nodes are rendered from a fixed, internal badge tree shipped with
  # the app. Tags, attrs, and children do not come from request parameters.
  defp render_logo(%{tag: tag, attrs: attrs, children: children}) do
    Phoenix.HTML.raw([
      "<",
      Atom.to_string(tag),
      render_attrs(attrs),
      ">",
      Enum.map(children, &render_logo_iodata/1),
      "</",
      Atom.to_string(tag),
      ">"
    ])
  end

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

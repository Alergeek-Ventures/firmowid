defmodule FirmowidUI.Components.Link do
  @moduledoc """
  App-owned link primitive for the design system.

  The component supports three visual kinds:

  - `kind="unstyled"` for semantic links that keep local styling
  - `kind="text"` for Figma-aligned text links
  - `kind="button"` for links styled like design-system buttons

  The supported navigation targets are explicit:

  - `navigate` for LiveView navigation
  - `patch` for in-place LiveView URL updates
  - `redirect` for full document navigation to internal routes
  - `external` for absolute external URLs (`http://` or `https://`)
  - `mailto` for e-mail links

  Invalid attribute combinations, such as two targets or a variant on a non-button
  link, are intentionally not handled by fallback clauses: they raise a function
  clause error, so the supported API should be treated as strict and explicit.
  """

  use FirmowidUI, :html

  alias FirmowidUI.Utilities.ButtonStyles

  @button_variants ~w(special primary secondary tertiary outline ghost destructive success plain)
  @accents ~w(rust teal)
  @kinds ~w(unstyled text button)
  @sizes ~w(big small)

  @doc """
  Renders a design-system link.

  ## Examples

      <.link kind="unstyled" navigate={~p"/ustawienia"}>Ustawienia</.link>
      <.link kind="text" patch={~p"/zarzadzanie/projekty?archiwum=1"} size="small">Archiwum</.link>
      <.link kind="button" navigate={~p"/zarzadzanie/projekty/dodaj"} variant="secondary">
        Dodaj projekt
      </.link>
      <.link redirect={~p"/auth/user/google"} kind="button" variant="outline">
        Kontynuuj z Google
      </.link>
      <.link kind="unstyled" external="https://firmowid.pl">Firmowid</.link>
      <.link kind="unstyled" mailto="contact@alergeek.ventures">Skontaktuj się</.link>
  """
  @spec link(map()) :: Phoenix.LiveView.Rendered.t()
  attr :class, :any, default: nil, doc: "Additional classes merged into the component."

  attr :rest, :global,
    include:
      ~w(aria-label target rel download phx-click phx-disable-with referrerpolicy style data-landing-cta data-landing-plan data-landing-billing-period)

  attr :kind, :string,
    values: @kinds,
    required: true,
    doc: "Visual kind of the link."

  attr :size, :string,
    default: "big",
    values: @sizes,
    doc: "Figma-aligned size modifier shared by text and button links."

  attr :variant, :any,
    default: nil,
    doc:
      "Design-system button variant. Supported only for `kind=\"button\"` and expected to be one of #{inspect(@button_variants)}."

  attr :accent, :any,
    default: nil,
    doc: "Accent used by button links that support multiple colorways and expected to be one of #{inspect(@accents)}."

  attr :navigate, :any, default: nil
  attr :patch, :any, default: nil
  attr :redirect, :string, default: nil
  attr :external, :string, default: nil
  attr :mailto, :string, default: nil

  slot :inner_block, required: true

  def link(assigns) do
    assigns =
      assigns
      |> assign(:href, href(assigns))
      |> assign(:link_classes, link_classes(assigns))

    ~H"""
    <Phoenix.Component.link
      navigate={@navigate}
      patch={@patch}
      href={@href}
      class={[@link_classes, @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </Phoenix.Component.link>
    """
  end

  defp href(%{patch: nil, redirect: nil, external: nil, mailto: nil}), do: nil
  defp href(%{navigate: nil, redirect: nil, external: nil, mailto: nil}), do: nil

  defp href(%{navigate: nil, patch: nil, redirect: redirect, external: nil, mailto: nil}), do: redirect

  defp href(%{navigate: nil, patch: nil, redirect: nil, external: "http://" <> _ = external, mailto: nil}), do: external

  defp href(%{navigate: nil, patch: nil, redirect: nil, external: "https://" <> _ = external, mailto: nil}), do: external

  defp href(%{navigate: nil, patch: nil, redirect: nil, external: nil, mailto: mailto})
       when is_binary(mailto) and byte_size(mailto) > 0, do: "mailto:" <> mailto

  defp link_classes(%{kind: "unstyled", variant: nil, accent: nil}), do: nil

  defp link_classes(%{kind: "text", variant: nil, accent: nil, size: size}) do
    [
      "inline-flex items-center justify-center gap-1 whitespace-nowrap select-none transition duration-100 ease-out",
      text_size_classes(size),
      "font-normal text-grey-700",
      "hover:text-grey-900 active:text-rust-700",
      "[&>svg]:size-4"
    ]
  end

  defp link_classes(%{kind: "button", size: size, variant: variant, accent: accent}) do
    [
      "inline-flex items-center justify-center whitespace-nowrap select-none border transition duration-100 ease-out cursor-pointer disabled:pointer-events-none disabled:cursor-default phx-click-loading:opacity-75 phx-click-loading:cursor-default",
      ButtonStyles.size_classes(size),
      ButtonStyles.variant_classes(variant || "primary", accent)
    ]
  end

  defp text_size_classes("big"), do: "text-base/tight"
  defp text_size_classes("small"), do: "text-sm/tight"
end

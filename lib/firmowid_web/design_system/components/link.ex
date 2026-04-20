defmodule FirmowidWeb.DesignSystem.Components.Link do
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

  Invalid attribute combinations are intentionally not handled by fallback clauses.
  They fail via function clause mismatch, so the supported API should be treated as
  strict and explicit.
  """

  use FirmowidWeb, :html

  alias FirmowidWeb.DesignSystem.Utilities.ButtonStyles

  @button_variants ~w(special primary secondary tertiary outline ghost destructive success)
  @accents ~w(orange turquoise)
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

  attr :rest, :global, include: ~w(aria-label target rel phx-click phx-disable-with referrerpolicy)

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

  def link(assigns), do: render_link(assigns)

  defp render_link(
         %{
           kind: "unstyled",
           variant: nil,
           accent: nil,
           navigate: navigate,
           patch: nil,
           redirect: nil,
           external: nil,
           mailto: nil
         } = assigns
       ) do
    assigns
    |> assign(:navigate, navigate)
    |> assign(:link_classes, nil)
    |> do_render_navigate_link()
  end

  defp render_link(
         %{
           kind: "unstyled",
           variant: nil,
           accent: nil,
           navigate: nil,
           patch: patch,
           redirect: nil,
           external: nil,
           mailto: nil
         } = assigns
       ) do
    assigns
    |> assign(:patch, patch)
    |> assign(:link_classes, nil)
    |> do_render_patch_link()
  end

  defp render_link(
         %{
           kind: "unstyled",
           variant: nil,
           accent: nil,
           navigate: nil,
           patch: nil,
           redirect: redirect,
           external: nil,
           mailto: nil
         } = assigns
       ) do
    assigns
    |> assign(:redirect, redirect)
    |> assign(:link_classes, nil)
    |> do_render_redirect_link()
  end

  defp render_link(
         %{
           kind: "unstyled",
           variant: nil,
           accent: nil,
           navigate: nil,
           patch: nil,
           redirect: nil,
           external: "http://" <> _external,
           mailto: nil
         } = assigns
       ) do
    assigns
    |> assign(:link_classes, nil)
    |> do_render_external_link()
  end

  defp render_link(
         %{
           kind: "unstyled",
           variant: nil,
           accent: nil,
           navigate: nil,
           patch: nil,
           redirect: nil,
           external: "https://" <> _external,
           mailto: nil
         } = assigns
       ) do
    assigns
    |> assign(:link_classes, nil)
    |> do_render_external_link()
  end

  defp render_link(
         %{
           kind: "unstyled",
           variant: nil,
           accent: nil,
           navigate: nil,
           patch: nil,
           redirect: nil,
           external: nil,
           mailto: mailto
         } = assigns
       )
       when is_binary(mailto) and byte_size(mailto) > 0 do
    assigns
    |> assign(:mailto_href, "mailto:" <> mailto)
    |> assign(:link_classes, nil)
    |> do_render_mailto_link()
  end

  defp render_link(
         %{
           kind: "text",
           size: size,
           variant: nil,
           accent: nil,
           navigate: navigate,
           patch: nil,
           redirect: nil,
           external: nil,
           mailto: nil
         } = assigns
       ) do
    assigns
    |> assign(:navigate, navigate)
    |> assign(:link_classes, text_link_classes(size))
    |> do_render_navigate_link()
  end

  defp render_link(
         %{
           kind: "text",
           size: size,
           variant: nil,
           accent: nil,
           navigate: nil,
           patch: patch,
           redirect: nil,
           external: nil,
           mailto: nil
         } = assigns
       ) do
    assigns
    |> assign(:patch, patch)
    |> assign(:link_classes, text_link_classes(size))
    |> do_render_patch_link()
  end

  defp render_link(
         %{
           kind: "text",
           size: size,
           variant: nil,
           accent: nil,
           navigate: nil,
           patch: nil,
           redirect: redirect,
           external: nil,
           mailto: nil
         } = assigns
       ) do
    assigns
    |> assign(:redirect, redirect)
    |> assign(:link_classes, text_link_classes(size))
    |> do_render_redirect_link()
  end

  defp render_link(
         %{
           kind: "text",
           size: size,
           variant: nil,
           accent: nil,
           navigate: nil,
           patch: nil,
           redirect: nil,
           external: "http://" <> _external,
           mailto: nil
         } = assigns
       ) do
    assigns
    |> assign(:link_classes, text_link_classes(size))
    |> do_render_external_link()
  end

  defp render_link(
         %{
           kind: "text",
           size: size,
           variant: nil,
           accent: nil,
           navigate: nil,
           patch: nil,
           redirect: nil,
           external: "https://" <> _external,
           mailto: nil
         } = assigns
       ) do
    assigns
    |> assign(:link_classes, text_link_classes(size))
    |> do_render_external_link()
  end

  defp render_link(
         %{
           kind: "text",
           size: size,
           variant: nil,
           accent: nil,
           navigate: nil,
           patch: nil,
           redirect: nil,
           external: nil,
           mailto: mailto
         } = assigns
       )
       when is_binary(mailto) and byte_size(mailto) > 0 do
    assigns
    |> assign(:mailto_href, "mailto:" <> mailto)
    |> assign(:link_classes, text_link_classes(size))
    |> do_render_mailto_link()
  end

  defp render_link(
         %{kind: "button", size: size, navigate: navigate, patch: nil, redirect: nil, external: nil, mailto: nil} =
           assigns
       ) do
    assigns
    |> assign(:navigate, navigate)
    |> assign(:variant, assigns.variant || "primary")
    |> assign(:accent, assigns.accent || "orange")
    |> assign(
      :link_classes,
      button_link_classes(size, assigns.variant || "primary", assigns.accent || "orange")
    )
    |> do_render_navigate_link()
  end

  defp render_link(
         %{kind: "button", size: size, navigate: nil, patch: patch, redirect: nil, external: nil, mailto: nil} = assigns
       ) do
    assigns
    |> assign(:patch, patch)
    |> assign(:variant, assigns.variant || "primary")
    |> assign(:accent, assigns.accent || "orange")
    |> assign(
      :link_classes,
      button_link_classes(size, assigns.variant || "primary", assigns.accent || "orange")
    )
    |> do_render_patch_link()
  end

  defp render_link(
         %{kind: "button", size: size, navigate: nil, patch: nil, redirect: redirect, external: nil, mailto: nil} =
           assigns
       ) do
    assigns
    |> assign(:redirect, redirect)
    |> assign(:variant, assigns.variant || "primary")
    |> assign(:accent, assigns.accent || "orange")
    |> assign(
      :link_classes,
      button_link_classes(size, assigns.variant || "primary", assigns.accent || "orange")
    )
    |> do_render_redirect_link()
  end

  defp render_link(
         %{
           kind: "button",
           size: size,
           navigate: nil,
           patch: nil,
           redirect: nil,
           external: "http://" <> _external,
           mailto: nil
         } = assigns
       ) do
    assigns
    |> assign(:variant, assigns.variant || "primary")
    |> assign(:accent, assigns.accent || "orange")
    |> assign(
      :link_classes,
      button_link_classes(size, assigns.variant || "primary", assigns.accent || "orange")
    )
    |> do_render_external_link()
  end

  defp render_link(
         %{
           kind: "button",
           size: size,
           navigate: nil,
           patch: nil,
           redirect: nil,
           external: "https://" <> _external,
           mailto: nil
         } = assigns
       ) do
    assigns
    |> assign(:variant, assigns.variant || "primary")
    |> assign(:accent, assigns.accent || "orange")
    |> assign(
      :link_classes,
      button_link_classes(size, assigns.variant || "primary", assigns.accent || "orange")
    )
    |> do_render_external_link()
  end

  defp render_link(
         %{kind: "button", size: size, navigate: nil, patch: nil, redirect: nil, external: nil, mailto: mailto} = assigns
       )
       when is_binary(mailto) and byte_size(mailto) > 0 do
    assigns
    |> assign(:mailto_href, "mailto:" <> mailto)
    |> assign(:variant, assigns.variant || "primary")
    |> assign(:accent, assigns.accent || "orange")
    |> assign(
      :link_classes,
      button_link_classes(size, assigns.variant || "primary", assigns.accent || "orange")
    )
    |> do_render_mailto_link()
  end

  defp do_render_navigate_link(assigns) do
    ~H"""
    <Phoenix.Component.link navigate={@navigate} class={[@link_classes, @class]} {@rest}>
      {render_slot(@inner_block)}
    </Phoenix.Component.link>
    """
  end

  defp do_render_patch_link(assigns) do
    ~H"""
    <Phoenix.Component.link patch={@patch} class={[@link_classes, @class]} {@rest}>
      {render_slot(@inner_block)}
    </Phoenix.Component.link>
    """
  end

  defp do_render_redirect_link(assigns) do
    ~H"""
    <Phoenix.Component.link href={@redirect} class={[@link_classes, @class]} {@rest}>
      {render_slot(@inner_block)}
    </Phoenix.Component.link>
    """
  end

  defp do_render_external_link(assigns) do
    ~H"""
    <Phoenix.Component.link href={@external} class={[@link_classes, @class]} {@rest}>
      {render_slot(@inner_block)}
    </Phoenix.Component.link>
    """
  end

  defp do_render_mailto_link(assigns) do
    ~H"""
    <Phoenix.Component.link href={@mailto_href} class={[@link_classes, @class]} {@rest}>
      {render_slot(@inner_block)}
    </Phoenix.Component.link>
    """
  end

  defp text_link_classes("big") do
    [
      "inline-flex items-center justify-center gap-1 whitespace-nowrap select-none transition duration-100 ease-out",
      "text-base/tight font-medium text-grey-700",
      "hover:text-grey-900 active:text-orange-700",
      "[&>svg]:size-4"
    ]
  end

  defp text_link_classes("small") do
    [
      "inline-flex items-center justify-center gap-1 whitespace-nowrap select-none transition duration-100 ease-out",
      "text-sm/tight font-medium text-grey-700",
      "hover:text-grey-900 active:text-orange-700",
      "[&>svg]:size-4"
    ]
  end

  defp button_link_classes(size, variant, accent) do
    [
      "inline-flex items-center justify-center whitespace-nowrap select-none border transition duration-100 ease-out cursor-pointer disabled:pointer-events-none disabled:cursor-default phx-click-loading:opacity-75 phx-click-loading:cursor-default",
      ButtonStyles.size_classes(size),
      ButtonStyles.variant_classes(variant, accent)
    ]
  end
end

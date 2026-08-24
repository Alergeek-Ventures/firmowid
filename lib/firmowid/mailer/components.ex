defmodule Firmowid.Mailer.Components do
  @moduledoc "Composable Phoenix components for Firmowid transactional emails."

  use Phoenix.Component

  import FirmowidWeb.DesignSystem.Components.Link
  import Phoenix.Component, except: [link: 1]

  @dark "#292929"
  @light_grey "#F5F5F5"

  attr :preheader, :string, required: true
  slot :inner_block, required: true

  @doc "Renders the shared shell around transactional email content."
  def email(assigns) do
    assigns =
      assign(assigns,
        background: @light_grey,
        ink: @dark,
        logo_url: static_url("images/logo_firmowid.png")
      )

    ~H"""
    <!doctype html>
    <html lang="pl">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="color-scheme" content="light only" />
        <title>Firmowid</title>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
        <link
          href="https://fonts.googleapis.com/css2?family=Lexend:wght@300;400;500;600;700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body style={"margin:0; padding:0; background:#{@background}; color:#{@ink}; font-family:'Lexend', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;"}>
        <div style="display:none; max-height:0; overflow:hidden; opacity:0;">{@preheader}</div>
        <table
          role="presentation"
          width="100%"
          cellspacing="0"
          cellpadding="0"
          border="0"
          style={"width:100%; background:#{@background}; border-collapse:collapse; font-family:'Lexend', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;"}
        >
          <tr>
            <td align="center">
              <table
                role="presentation"
                cellspacing="0"
                cellpadding="0"
                border="0"
                style={"width:100%; border-collapse:collapse; background:#{@background};"}
              >
                <tr>
                  <td align="center" style="padding:40px 20px;">
                    <table
                      role="presentation"
                      width="100%"
                      cellspacing="0"
                      cellpadding="0"
                      border="0"
                      style="width:100%; max-width:640px; border-collapse:collapse; background:#FFFFFF; box-shadow:0 2px 8px rgba(0,0,0,0.08);"
                    >
                      <tr>
                        <td style="padding:32px 40px 20px 40px; text-align:center;">
                          <img
                            src={@logo_url}
                            alt="Firmowid"
                            style="height:40px; width:auto;"
                          />
                        </td>
                      </tr>
                      <tr>
                        <td style="padding:8px 40px 12px 40px;">
                          {render_slot(@inner_block)}
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
  end

  slot :inner_block, required: true

  @doc "Renders the email greeting."
  def greeting(assigns) do
    ~H"""
    <h1 style="margin:0; font-size:28px; line-height:1.2; font-weight:600; color: #292929;">
      {render_slot(@inner_block)}
    </h1>
    """
  end

  slot :inner_block, required: true

  @doc "Renders a primary paragraph."
  def paragraph(assigns) do
    ~H"""
    <p style="margin:0; max-width:420px; font-size:16px; line-height:1.7; color: #707070;">
      {render_slot(@inner_block)}
    </p>
    """
  end

  slot :inner_block, required: true

  @doc "Renders a paragraph with top margin."
  def paragraph_spaced(assigns) do
    ~H"""
    <p style="margin:12px 0 0; max-width:420px; font-size:16px; line-height:1.7; color: #707070;">
      {render_slot(@inner_block)}
    </p>
    """
  end

  attr :href, :string, required: true
  slot :inner_block, required: true

  @doc "Renders a primary email button."
  def button(assigns) do
    ~H"""
    <table
      role="presentation"
      cellspacing="0"
      cellpadding="0"
      border="0"
      style="border-collapse:collapse; margin:32px 0;"
    >
      <tr>
        <td align="center" style="padding:16px 0 24px 0;">
          <.link
            kind="unstyled"
            external={@href}
            target="_blank"
            style="display:inline-block; background-color:#292929; color:#FFFFFF; text-decoration:none; padding:14px 20px; font-size:16px; font-weight:500;"
          >
            {render_slot(@inner_block)}
          </.link>
        </td>
      </tr>
    </table>
    """
  end

  attr :href, :string, required: true

  @doc "Renders a copyable fallback for the primary action."
  def fallback_link(assigns) do
    ~H"""
    <p style="margin:0; font-size:14px; line-height:1.7; color: #707070;">
      Jeśli przycisk nie działa, wklej ten link w przeglądarkę:<br />
      <.link
        kind="unstyled"
        external={@href}
        target="_blank"
        style="color:#292929; text-decoration:underline; word-break:break-all;"
      >{@href}</.link>
    </p>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  @doc "Renders a key-value detail row."
  def detail_row(assigns) do
    ~H"""
    <table
      role="presentation"
      style="width:100%; border-collapse:collapse; border-top:1px solid #ECECEC;"
    >
      <tr>
        <td style="padding:12px 0; border-bottom:1px solid #ECECEC; width:140px; vertical-align:top; font-size:15px; color: #707070;">
          {@label}
        </td>
        <td style="padding:12px 0; border-bottom:1px solid #ECECEC; vertical-align:top; font-size:15px; line-height:1.6; color: #292929; font-weight:500;">
          {@value}
        </td>
      </tr>
    </table>
    """
  end

  slot :inner_block, required: true

  @doc "Renders secondary information below the main content."
  def note(assigns) do
    ~H"""
    <p style="margin:20px 0 0; font-size:14px; line-height:1.7; color: #707070;">
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc "Renders the Firmowid team signature."
  def signature(assigns) do
    ~H"""
    <p style="margin:48px 0 32px; text-align:right; font-size:14px; line-height:1.25; color: #292929;">
      Pozdrawiamy,<br />Zespół Firmowid
    </p>
    """
  end

  @doc "Converts a rendered email component into a string accepted by Swoosh."
  @spec to_html(Phoenix.LiveView.Rendered.t()) :: String.t()
  def to_html(rendered) do
    rendered
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp static_url(path) do
    Phoenix.VerifiedRoutes.static_url(FirmowidWeb.Core.Endpoint, "/#{path}")
  end
end

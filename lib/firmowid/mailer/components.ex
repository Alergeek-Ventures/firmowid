defmodule Firmowid.Mailer.Components do
  @moduledoc """
  Composable Phoenix components for Firmowid transactional emails.

  The markup is email-client HTML: tables, inline styles and a 680px column.
  Two-column blocks are inline-block `div`s that stack on narrow screens,
  wrapped in Outlook-only tables because Outlook ignores `max-width`.
  """

  use Phoenix.Component

  import FirmowidUI.Components.Link
  import Phoenix.Component, except: [link: 1]

  @font "Lexend, Arial, Helvetica, sans-serif"
  @ink "#1A1A1A"
  @graphite "#4E4E4E"
  @pebble "#707070"
  @line "#DDDDDD"
  @paper "#F5F1EA"

  # Rasterized at 2x from the landing characters; width and height are the displayed size.
  # The figures are decorative (the headline carries the message), so their alt is empty
  # and image-blocking clients show nothing in either language.
  @figures %{
    invoice: %{
      path: "images/email/swiatowid-faktura.png",
      width: 112,
      height: 198
    },
    hourglass: %{
      path: "images/email/swiatowid-klepsydra.png",
      width: 112,
      height: 211
    },
    suitcase: %{
      path: "images/email/swiatowid-walizka.png",
      width: 112,
      height: 209
    }
  }

  @button_colors %{sales: "#455E5E", cost: "#8B3F13", neutral: @graphite}

  @mobile_css """
  :root { color-scheme: light only; supported-color-schemes: light only; }
  body { margin: 0 !important; padding: 0 !important; width: 100% !important; }
  a[x-apple-data-detectors] { color: inherit !important; text-decoration: none !important; }
  @media only screen and (max-width: 640px) {
    .px { padding-left: 20px !important; padding-right: 20px !important; }
    .head-text-col { width: 74% !important; max-width: 74% !important; }
    .head-fig-col { width: 26% !important; max-width: 26% !important; }
    .head-text { padding: 24px 8px 24px 20px !important; }
    .head-fig { padding: 16px 20px 0 0 !important; }
    .head-fig img { width: 100% !important; max-width: 64px !important; height: auto !important; }
    .h1 { font-size: 23px !important; }
    .col { display: block !important; width: 100% !important; max-width: 100% !important; }
    .col-left { padding: 0 !important; }
    .col-right { padding: 24px 0 0 !important; }
    .hide-sm { display: none !important; }
    .amount { font-size: 34px !important; line-height: 40px !important; }
  }
  """

  attr :preheader, :string, required: true
  attr :lang, :string, default: "pl"
  attr :figure, :atom, default: nil, values: [nil | Map.keys(@figures)]
  slot :headline, required: true
  slot :lead
  slot :inner_block, required: true
  slot :footer

  @doc """
  Renders the shared shell: a full-width paper band with the Firmowid mark, the
  headline and an optional Światowid figure, then the white body and footer.
  """
  # sobelow_skip ["XSS.Raw"]
  # raw/1 only emits the module's constant @mobile_css; HEEx cannot interpolate
  # inside <style>, and no user input reaches it.
  def email(assigns) do
    assigns =
      assign(assigns,
        css: @mobile_css,
        head_url: static_url("images/email/firmowid-head.png"),
        figure_image: figure_image(assigns.figure),
        text_width: if(assigns.figure, do: 528, else: 680)
      )

    ~H"""
    <!doctype html>
    <html lang={@lang}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="x-apple-disable-message-reformatting" />
        <meta name="format-detection" content="telephone=no, date=no, address=no, email=no" />
        <meta name="color-scheme" content="light only" />
        <meta name="supported-color-schemes" content="light only" />
        <title>Firmowid</title>
        <%!-- HEEx does not interpolate inside <style>, so the whole tag is emitted raw. --%>
        {Phoenix.HTML.raw("<style>" <> @css <> "</style>")}
      </head>
      <body style="margin:0; padding:0; background:#FFFFFF; -webkit-text-size-adjust:100%;">
        <div style="display:none; max-height:0; max-width:0; overflow:hidden; opacity:0; mso-hide:all; font-size:1px; line-height:1px; color:#FFFFFF;">
          {@preheader}
        </div>
        <table
          role="presentation"
          width="100%"
          cellspacing="0"
          cellpadding="0"
          border="0"
          style="width:100%; background:#FFFFFF; border-collapse:collapse;"
        >
          <tr>
            <td align="center" bgcolor={paper()} style={"background:#{paper()}; padding:0;"}>
              <!--[if mso]><table role="presentation" width="680" cellspacing="0" cellpadding="0" border="0"><tr><td><![endif]-->
              <table
                role="presentation"
                width="100%"
                cellspacing="0"
                cellpadding="0"
                border="0"
                style="width:100%; max-width:680px; border-collapse:collapse;"
              >
                <tr>
                  <td valign="bottom" style="font-size:0; text-align:left;">
                    <%!-- Outlook ignores max-width, so it gets real cells for the two header columns. --%>
                    <%= if @figure_image do %>
                      <!--[if mso]><table role="presentation" width="680" cellspacing="0" cellpadding="0" border="0"><tr><td width="528" valign="top"><![endif]-->
                    <% end %>
                    <div
                      class={[@figure_image && "head-text-col"]}
                      style={"display:inline-block; width:100%; max-width:#{@text_width}px; vertical-align:top;"}
                    >
                      <table
                        role="presentation"
                        width="100%"
                        cellspacing="0"
                        cellpadding="0"
                        border="0"
                      >
                        <tr>
                          <td class="head-text" style="padding:28px 16px 32px 40px;">
                            <table role="presentation" cellspacing="0" cellpadding="0" border="0">
                              <tr>
                                <td width="40" valign="middle" style="width:40px;">
                                  <img
                                    src={@head_url}
                                    width="40"
                                    height="40"
                                    alt=""
                                    style="display:block; width:40px; height:40px; border:0;"
                                  />
                                </td>
                                <td
                                  valign="middle"
                                  style={"padding-left:10px; font-family:#{font()}; font-size:19px; line-height:24px; font-weight:600; color:#{ink()};"}
                                >
                                  Firmowid
                                </td>
                              </tr>
                            </table>
                            <h1
                              class="h1"
                              style={"margin:32px 0 0; font-family:#{font()}; font-size:30px; line-height:1.2; font-weight:700; letter-spacing:-0.6px; color:#{ink()};"}
                            >
                              {render_slot(@headline)}
                            </h1>
                            <p
                              :if={@lead != []}
                              style={"margin:10px 0 0; font-family:#{font()}; font-size:16px; line-height:24px; color:#{graphite()};"}
                            >
                              {render_slot(@lead)}
                            </p>
                          </td>
                        </tr>
                      </table>
                    </div>
                    <%= if @figure_image do %>
                      <!--[if mso]></td><td width="152" valign="bottom"><![endif]-->
                    <% end %>
                    <div
                      :if={@figure_image}
                      class="head-fig-col"
                      style="display:inline-block; width:100%; max-width:152px; vertical-align:bottom; text-align:right;"
                    >
                      <table
                        role="presentation"
                        width="100%"
                        cellspacing="0"
                        cellpadding="0"
                        border="0"
                      >
                        <tr>
                          <td class="head-fig" align="right" style="padding:20px 40px 0 0;">
                            <img
                              src={@figure_image.url}
                              width={@figure_image.width}
                              height={@figure_image.height}
                              alt=""
                              style={"display:block; width:#{@figure_image.width}px; height:#{@figure_image.height}px; border:0;"}
                            />
                          </td>
                        </tr>
                      </table>
                    </div>
                    <%= if @figure_image do %>
                      <!--[if mso]></td></tr></table><![endif]-->
                    <% end %>
                  </td>
                </tr>
              </table>
              <!--[if mso]></td></tr></table><![endif]-->
            </td>
          </tr>
          <tr>
            <td align="center" style="padding:0 0 32px;">
              <!--[if mso]><table role="presentation" width="680" cellspacing="0" cellpadding="0" border="0"><tr><td><![endif]-->
              <table
                role="presentation"
                width="100%"
                cellspacing="0"
                cellpadding="0"
                border="0"
                style="width:100%; max-width:680px; border-collapse:collapse;"
              >
                <tr>
                  <td class="px" style="padding:36px 40px 32px; text-align:left;">
                    {render_slot(@inner_block)}
                  </td>
                </tr>
                <tr :if={@footer != []}>
                  <td class="px" style="padding:0 40px 28px;">
                    <div style={"border-top:1px solid #{line()}; padding-top:16px;"}>
                      {render_slot(@footer)}
                    </div>
                  </td>
                </tr>
              </table>
              <!--[if mso]></td></tr></table><![endif]-->
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
  end

  slot :inner_block, required: true

  @doc "Renders a body paragraph."
  def paragraph(assigns) do
    ~H"""
    <p style={"margin:0 0 16px; font-family:#{font()}; font-size:16px; line-height:24px; color:#{graphite()};"}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  @doc "Renders a short quotation from a person, such as a request reason, under a label."
  def quotation(assigns) do
    ~H"""
    <p style={"margin:0; font-family:#{font()}; font-size:13px; line-height:18px; color:#{pebble()};"}>
      {@label}
    </p>
    <p style={"margin:4px 0 20px; font-family:#{font()}; font-size:18px; line-height:27px; color:#{ink()};"}>
      „{render_slot(@inner_block)}”
    </p>
    """
  end

  attr :href, :string, required: true
  attr :tone, :atom, default: :neutral, values: Map.keys(@button_colors)
  slot :inner_block, required: true

  @doc """
  Renders the email's primary action. The tone follows the ledger colours:
  `:sales` (teal), `:cost` (rust) or `:neutral` (graphite).
  """
  def button(assigns) do
    assigns = assign(assigns, :color, Map.fetch!(@button_colors, assigns.tone))

    ~H"""
    <table role="presentation" cellspacing="0" cellpadding="0" border="0" style="margin-top:24px;">
      <tr>
        <td align="center" bgcolor={@color} style={"background:#{@color}; border-radius:8px;"}>
          <.link
            kind="unstyled"
            external={@href}
            target="_blank"
            style={"display:block; padding:15px 28px; font-family:#{font()}; font-size:16px; line-height:20px; font-weight:600; color:#FFFFFF; text-decoration:none; border-radius:8px;"}
          >
            {render_slot(@inner_block)}
          </.link>
        </td>
      </tr>
    </table>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, default: "Jeśli przycisk nie działa, otwórz link:"

  @doc "Renders a copyable fallback for the primary action, for the footer."
  def fallback_link(assigns) do
    ~H"""
    <p style={"margin:0; font-family:#{font()}; font-size:12px; line-height:18px; color:#{pebble()};"}>
      {@label}
      <.link
        kind="unstyled"
        external={@href}
        target="_blank"
        style={"color:#{graphite()}; text-decoration:underline; word-break:break-all;"}
      >{@href}</.link>
    </p>
    """
  end

  slot :inner_block, required: true

  @doc "Renders secondary footer text, such as why the recipient gets the email."
  def note(assigns) do
    ~H"""
    <p style={"margin:0 0 12px; font-family:#{font()}; font-size:14px; line-height:22px; color:#{graphite()};"}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true

  @doc "Renders a key-value detail row separated from the next one by a hairline."
  def detail_row(assigns) do
    ~H"""
    <table
      role="presentation"
      width="100%"
      cellspacing="0"
      cellpadding="0"
      border="0"
      style="border-collapse:collapse;"
    >
      <tr>
        <td
          width="160"
          valign="top"
          style={"width:160px; padding:10px 16px 10px 0; border-bottom:1px solid #{line()}; font-family:#{font()}; font-size:14px; line-height:22px; color:#{pebble()};"}
        >
          {@label}
        </td>
        <td
          valign="top"
          style={"padding:10px 0; border-bottom:1px solid #{line()}; font-family:#{font()}; font-size:15px; line-height:22px; font-weight:500; color:#{ink()};"}
        >
          {@value}
        </td>
      </tr>
    </table>
    """
  end

  slot :left, required: true
  slot :right, required: true

  @doc """
  Renders two columns (316px and 284px, the 600px body) that sit side by side
  on desktop and stack on phones.
  """
  def columns(assigns) do
    ~H"""
    <div style="font-size:0; text-align:left;">
      <!--[if mso]><table role="presentation" width="600" cellspacing="0" cellpadding="0" border="0"><tr><td width="316" valign="top"><![endif]-->
      <div
        class="col"
        style="display:inline-block; width:100%; max-width:316px; vertical-align:top;"
      >
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
          <tr>
            <td class="col-left" style="padding:0 32px 0 0;">{render_slot(@left)}</td>
          </tr>
        </table>
      </div>
      <!--[if mso]></td><td valign="top"><![endif]-->
      <div
        class="col"
        style="display:inline-block; width:100%; max-width:284px; vertical-align:top;"
      >
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
          <tr>
            <td class="col-right" style="padding:0;">{render_slot(@right)}</td>
          </tr>
        </table>
      </div>
      <!--[if mso]></td></tr></table><![endif]-->
    </div>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  @doc "Renders a small grey label above a value, for blocks inside `columns/1`."
  def field(assigns) do
    ~H"""
    <p style={"margin:0; font-family:#{font()}; font-size:13px; line-height:18px; color:#{pebble()};"}>
      {@label}
    </p>
    <div style={"margin:2px 0 16px; font-family:#{font()}; font-size:15px; line-height:22px; font-weight:500; color:#{ink()};"}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "Converts a rendered email component into a string accepted by Swoosh."
  @spec to_html(Phoenix.LiveView.Rendered.t()) :: String.t()
  def to_html(rendered) do
    rendered
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  @doc "Font stack for inline styles in email templates."
  @spec font() :: String.t()
  def font, do: @font

  @doc "Strongest text colour."
  @spec ink() :: String.t()
  def ink, do: @ink

  @doc "Body text colour."
  @spec graphite() :: String.t()
  def graphite, do: @graphite

  @doc "Secondary and label text colour."
  @spec pebble() :: String.t()
  def pebble, do: @pebble

  @doc "Hairline colour for separators."
  @spec line() :: String.t()
  def line, do: @line

  @doc "Background of the header band."
  @spec paper() :: String.t()
  def paper, do: @paper

  defp figure_image(nil), do: nil

  defp figure_image(figure) do
    image = Map.fetch!(@figures, figure)
    Map.put(image, :url, static_url(image.path))
  end

  defp static_url(path) do
    Phoenix.VerifiedRoutes.static_url(FirmowidWeb.Core.Endpoint, "/#{path}")
  end
end

defmodule FirmowidWeb.Invoicing.SalesInvoices.Components.SharedPage do
  @moduledoc false
  use FirmowidWeb, :html

  embed_templates "shared_page/*"

  attr :title, :string, required: true
  attr :lang, :string, default: "pl"
  attr :body_class, :string, default: "bg-grey-100 min-h-full font-[Lexend]"
  slot :inner_block, required: true

  def shared_page(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang={@lang} class="h-full">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="robots" content="noindex, nofollow" />
        <title>{@title}</title>
        <link phx-track-static rel="stylesheet" href={~p"/assets/app.css"} />
      </head>

      <body class={@body_class}>
        <.navbar class="py-4">
          <.navbar_logo />
        </.navbar>
        {render_slot(@inner_block)}
      </body>
    </html>
    """
  end
end

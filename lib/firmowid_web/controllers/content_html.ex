defmodule FirmowidWeb.ContentHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use FirmowidWeb, :html

  embed_templates "content_html/*"
end

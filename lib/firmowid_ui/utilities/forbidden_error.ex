defmodule FirmowidUI.Utilities.ForbiddenError do
  @moduledoc """
  Raised when a signed-in user reaches an interface action their role does not allow.

  Rendered as 403 Forbidden.
  """
  defexception message: "Forbidden", plug_status: 403
end

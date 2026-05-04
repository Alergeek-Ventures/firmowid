defmodule FirmowidWeb.Invoicing.Assistant.Utilities.SessionCloser do
  @moduledoc """
  Closes assistant sessions from feature-local chat handlers.
  """

  alias Firmowid.Ash.Assistant.InvoiceMatching
  alias Firmowid.Ash.Scope

  @doc """
  Closes the assistant session referenced by close-chat params.
  """
  @spec close(map(), Scope.t()) :: :ok
  def close(%{"session_id" => session_id}, %Scope{} = scope) when is_binary(session_id) and session_id != "" do
    _ = InvoiceMatching.close_session(session_id, scope)
    :ok
  end

  def close(_params, _scope), do: :ok
end

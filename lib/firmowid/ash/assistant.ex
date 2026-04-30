defmodule Firmowid.Ash.Assistant do
  @moduledoc """
  Ash domain for universal assistant sessions and orchestration state.
  """

  use Ash.Domain

  resources do
    resource Firmowid.Ash.Assistant.Session do
      define :get_session, action: :by_id, args: [:id]
      define :list_sessions, action: :read
      define :start_session, action: :start_invoice_matching, args: [:entry_context]
      define :claim_session_processing, action: :claim_processing
      define :complete_session_turn, action: :complete_turn, args: [:messages]
      define :propose_session_match, action: :propose_match, args: [:messages, :pending_match]
      define :sync_pending_session_turn, action: :sync_pending_turn, args: [:messages]
      define :reject_session_match, action: :reject_match, args: [:messages]
      define :accept_session_match, action: :accept_match, args: [:messages]

      define :fail_session, action: :fail_session, args: [:last_error]

      define :close_session, action: :close
    end
  end

  authorization do
    authorize :by_default
    require_actor? true
  end
end

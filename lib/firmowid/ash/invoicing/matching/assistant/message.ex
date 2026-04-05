defmodule Firmowid.Ash.Invoicing.Matching.Assistant.Message do
  @moduledoc """
  Message struct for assistant conversations, replacing LlmComposer.Message.
  Now supports an optional :payload field for rich UI data.
  """
  @enforce_keys [:id, :role, :text, :timestamp]
  defstruct [:id, :role, :text, :payload, :timestamp]

  @type role :: :user | :assistant | :function_call | :function_result | :meta
  @type t :: %__MODULE__{
          id: String.t(),
          role: role(),
          text: String.t(),
          payload: any() | nil,
          timestamp: DateTime.t()
        }

  @doc """
  Creates a new message struct with a generated UUIDv7 id and current UTC timestamp.
  Only allows roles: :user, :assistant, :function_call, :function_result, :meta.
  """
  @spec new(role(), String.t(), any()) :: t()
  def new(role, text, payload \\ nil) do
    %__MODULE__{
      id: UUIDv7.generate(),
      role: role,
      text: text,
      payload: payload,
      timestamp: DateTime.utc_now()
    }
  end
end

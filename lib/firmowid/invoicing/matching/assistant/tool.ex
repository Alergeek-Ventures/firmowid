defmodule Firmowid.Invoicing.Matching.Assistant.Tool do
  @moduledoc """
  Struct for tools/functions that can be called by the LLM and UI.
  - :llm_render is a function that serializes the tool's output for the LLM (plain text)
  - :handler is a function that executes the tool logic (mf or fun)
  - :metadata is an optional map for extra info (e.g. UI hints)
  - :args_schema is a map describing the tool's argument schema
  """
  @enforce_keys [:name, :description, :args_schema, :llm_render, :handler]
  defstruct [
    :name,
    :description,
    :args_schema,
    :llm_render,
    :handler,
    :metadata
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          args_schema: map(),
          llm_render: (any() -> String.t()),
          handler: (map() -> any()),
          metadata: map() | nil
        }

  @doc """
  Converts a Tool struct to the OpenAI tool wire format (for use in the tools list).
  """
  @spec to_openai(t()) :: map()
  def to_openai(%__MODULE__{name: name, description: description, args_schema: args_schema}) do
    %{
      type: "function",
      function: %{
        name: name,
        description: description,
        parameters: args_schema
      }
    }
  end

  def to_openai_response(%__MODULE__{
        name: name,
        description: description,
        args_schema: args_schema
      }) do
    %{
      name: name,
      parameters: args_schema,
      type: "function",
      description: description
    }
  end
end

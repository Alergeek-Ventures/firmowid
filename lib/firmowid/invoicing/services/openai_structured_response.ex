defmodule Firmowid.Invoicing.Services.OpenAIStructuredResponse do
  @moduledoc """
  Asks a small OpenAI model, through the Responses API, for a JSON object that
  follows a schema, optionally after a required web search from Poland.
  """

  alias OpenaiEx.Responses

  @doc """
  Returns the decoded JSON answer. Raises when the request fails or the answer
  is not JSON. Pass `web_search: "low" | "medium"` (the search context size)
  to make the model search the web first.
  """
  @spec request!(String.t(), String.t(), map(), keyword()) :: map()
  def request!(instructions, input, format, opts \\ []) do
    request = %{
      model: "gpt-6-luna",
      reasoning: %{effort: "none"},
      # Web search calls count towards this limit.
      max_output_tokens: 1000,
      instructions: instructions,
      input: input,
      text: %{format: format}
    }

    request =
      case Keyword.get(opts, :web_search) do
        nil ->
          request

        # Left to choose, the model often skips the search and guesses from the name.
        context_size ->
          Map.merge(request, %{
            tools: [
              %{
                type: "web_search",
                search_context_size: context_size,
                user_location: %{type: "approximate", country: "PL"}
              }
            ],
            tool_choice: "required"
          })
      end

    client()
    |> Responses.create!(request)
    |> Map.fetch!("output")
    |> Enum.filter(&(&1["type"] == "message"))
    |> Enum.flat_map(& &1["content"])
    |> Enum.map_join(&(&1["text"] || ""))
    |> Jason.decode!()
  end

  defp client do
    openai =
      :firmowid
      |> Application.get_env(:openai_api_key)
      |> OpenaiEx.new()
      |> OpenaiEx.with_receive_timeout(60_000)

    case Application.get_env(:firmowid, :openai_ex, [])[:base_url] do
      base_url when is_binary(base_url) and base_url != "" ->
        OpenaiEx.with_base_url(openai, base_url)

      _ ->
        openai
    end
  end
end

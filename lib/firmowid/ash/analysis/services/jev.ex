defmodule Firmowid.Ash.Analysis.Services.Jev do
  @moduledoc "Bounded, server-only TypeSafe System One judgments without payload logging."

  @doc "Evaluates independent questions together for one entity; errors contain no request data."
  @spec evaluate(map(), map()) :: {:ok, map()} | {:error, atom()}
  def evaluate(state, questions) do
    case Application.get_env(:firmowid, :typesafe_api_key) do
      key when is_binary(key) and byte_size(key) > 0 -> request(key, state, questions)
      _ -> {:error, :typesafe_not_configured}
    end
  end

  defp request(key, state, questions) do
    case Req.post("https://api.typesafe.ai/v1/systemone",
           auth: {:bearer, key},
           json: %{model: "jev-latest", state: state, questions: questions},
           connect_options: [timeout: 5_000],
           receive_timeout: 30_000,
           redirect: false,
           retry: :transient,
           max_retries: 2
         ) do
      {:ok, %{status: 200, body: %{"answers" => answers}}} when is_map(answers) ->
        {:ok, answers}

      {:ok, %{status: status}} when status in [408, 429, 500, 502, 503, 504, 529] ->
        {:error, :typesafe_unavailable}

      {:ok, _response} ->
        {:error, :typesafe_rejected}

      {:error, _error} ->
        {:error, :typesafe_unavailable}
    end
  end
end

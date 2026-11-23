defmodule Firmowid.Core.Services.KrsApiClient do
  @moduledoc """
  Keyless KRS Open API of the Ministry of Justice (`api-krs.ms.gov.pl`), shared by
  company registration and the NIP check. It is searched by KRS number only, so the
  number has to come from elsewhere, e.g. the VAT white list.
  """

  @doc """
  Returns the data section (`odpis.dane`) of the current KRS extract, looking in the
  register of entrepreneurs (`P`) first and then in that of associations and
  foundations (`S`): `:struck_off` when no register has a current entry and one was
  struck off (KRS answers 204 with an empty extract), `:not_found` when neither
  register has the number.
  """
  @spec fetch_current(String.t()) :: {:ok, map() | :struck_off | :not_found} | {:error, term()}
  def fetch_current(krs) do
    # One number can have entries in both registers: a foundation struck off the register
    # of entrepreneurs when it stopped trading stays in that of associations and foundations.
    with {:ok, entrepreneurs} when not is_map(entrepreneurs) <- fetch_current(krs, "P"),
         {:ok, associations} when not is_map(associations) <- fetch_current(krs, "S") do
      {:ok, if(:struck_off in [entrepreneurs, associations], do: :struck_off, else: :not_found)}
    end
  end

  defp fetch_current(krs, registry) do
    options =
      Keyword.merge(
        [
          url: "https://api-krs.ms.gov.pl/api/krs/OdpisAktualny/#{krs}",
          params: [rejestr: registry, format: "json"],
          retry: false
        ],
        Application.get_env(:firmowid, :krs_api_request_options, [])
      )

    case Req.get(options) do
      {:ok, %{status: 200, body: %{"odpis" => %{"dane" => data}}}} -> {:ok, data}
      {:ok, %{status: 204}} -> {:ok, :struck_off}
      {:ok, %{status: 404}} -> {:ok, :not_found}
      # Includes a 200 with the HTML maintenance page instead of an extract.
      {:ok, %{status: status}} -> {:error, {:krs_http_error, status}}
      {:error, _reason} = error -> error
    end
  end
end

defmodule Firmowid.GoLimitless.ApiClient do
  @moduledoc """
  The GoLimitless ApiClient context.
  """
  alias Firmowid.GoLimitless.TokenManager

  def get_available_institutions() do
    token = get_access_token()
    IO.inspect(token)

    Req.get!(
      "https://bankaccountdata.gocardless.com/api/v2/institutions?country=pl",
      auth: {:bearer, token}
    )
    |> Map.get(:body)
  end

  defp get_access_token() do
    TokenManager.get_access_token()
  end
end

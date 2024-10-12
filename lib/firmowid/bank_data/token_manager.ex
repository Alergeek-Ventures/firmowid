defmodule Firmowid.BankData.TokenManager do
  use GenServer

  # seconds before expiry to refresh the token
  @refresh_buffer 60

  def get_access_token do
    case :ets.lookup(:token_table, :access_token) do
      [{:access_token, token}] -> token
      r -> IO.inspect(r)
    end
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    :ets.new(:token_table, [:named_table, :public, read_concurrency: true])
    schedule_token_refresh()
    {:ok, state}
  end

  @impl true
  def handle_info(:refresh_token, state) do
    {:ok, tokens} = fetch_new_access_token()

    :ets.insert(:token_table, {:access_token, tokens["access"]})
    :ets.insert(:token_table, {:refresh_token, tokens["refresh"]})
    :ets.insert(:token_table, {:access_expires, tokens["access_expires"]})
    :ets.insert(:token_table, {:refresh_expires, tokens["refresh_expires"]})

    {:noreply, state}
  end

  defp schedule_token_refresh do
    access_expires = :ets.lookup(:token_table, :access_expires)

    refresh_interval =
      case access_expires do
        [{:access_expires, expires_in}] ->
          expires_in - @refresh_buffer

        # default to refresh immiediately if token is no present
        _ ->
          1
      end

    Process.send_after(self(), :refresh_token, refresh_interval * 1000)
  end

  def fetch_new_access_token() do
    access_token_response =
      Req.post!(
        "https://bankaccountdata.gocardless.com/api/v2/token/new/",
        json: %{
          secret_id: Application.fetch_env!(:firmowid, :go_limitless_secret_id),
          secret_key: Application.fetch_env!(:firmowid, :go_limitless_secret_key)
        }
      )

    {:ok, access_token_response.body}
  end
end

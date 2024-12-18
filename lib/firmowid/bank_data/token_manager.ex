defmodule Firmowid.BankData.TokenManager do
  use GenServer

  # seconds before expiry to refresh the token
  @refresh_buffer 60

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    state = %{
      access_token: nil,
      access_expires: nil,
      refresh_token: nil,
      refresh_expires: nil
    }

    schedule_token_refresh(nil)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_access_token, _from, state) do
    access_token = state.access_token

    if is_nil(access_token) do
      state = fetch_new_access_token()
      schedule_token_refresh(state.refresh_expires)
      {:reply, state.access_token, state}
    else
      {:reply, access_token, state}
    end
  end

  @impl true
  def handle_info(:refresh_token, _state) do
    state = fetch_new_access_token()

    {:noreply, state}
  end

  defp fetch_new_access_token() do
    access_token_response =
      Req.post!(
        "https://bankaccountdata.gocardless.com/api/v2/token/new/",
        json: %{
          secret_id: Application.fetch_env!(:firmowid, :go_limitless_secret_id),
          secret_key: Application.fetch_env!(:firmowid, :go_limitless_secret_key)
        }
      )

    tokens = access_token_response.body

    %{
      access_token: tokens["access"],
      refresh_token: tokens["refresh"],
      access_expires: tokens["access_expires"],
      refresh_expires: tokens["refresh_expires"]
    }
  end

  defp schedule_token_refresh(refresh_expires) do
    refresh_interval =
      if is_nil(refresh_expires) do
        1
      else
        refresh_expires - @refresh_buffer
      end

    Process.send_after(self(), :refresh_token, refresh_interval * 1000)
  end
end

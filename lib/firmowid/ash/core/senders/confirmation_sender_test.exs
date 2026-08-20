defmodule Firmowid.Ash.Core.Senders.ConfirmationSenderTest do
  use ExUnit.Case, async: false

  alias Firmowid.Ash.Core.Senders.ConfirmationSender
  alias Firmowid.Ash.Core.User

  defmodule FailingAdapter do
    @moduledoc false
    use Swoosh.Adapter

    @impl Swoosh.Adapter
    def deliver(_email, _config), do: {:error, :delivery_failed}
  end

  test "returns the mail delivery error" do
    original_config = Application.get_env(:firmowid, Firmowid.Mailer)

    Application.put_env(
      :firmowid,
      Firmowid.Mailer,
      Keyword.put(original_config, :adapter, FailingAdapter)
    )

    on_exit(fn -> Application.put_env(:firmowid, Firmowid.Mailer, original_config) end)

    assert {:error, :delivery_failed} =
             ConfirmationSender.send(%User{email: "new@example.com"}, "token", [])
  end
end

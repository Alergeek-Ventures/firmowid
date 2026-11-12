defmodule Firmowid.Invoicing.Services.ResendAdapterTest do
  @moduledoc false
  use ExUnit.Case, async: true

  import Swoosh.Email

  alias Firmowid.Invoicing.Services.ResendAdapter

  test "sends the idempotency key to Resend next to the API key" do
    test_pid = self()

    Req.Test.stub(__MODULE__, fn conn ->
      send(test_pid, {:headers, conn.req_headers})
      Req.Test.json(conn, %{"id" => "email-1"})
    end)

    email =
      new()
      |> from({"Acme", "faktury@example.com"})
      |> to("billing@example.com")
      |> subject("Invoice FV/1")
      |> text_body("Invoice")
      |> put_provider_option(:idempotency_key, "sales-invoice-email-1")

    assert {:ok, %{id: "email-1"}} =
             ResendAdapter.deliver(email,
               api_key: "re_test",
               req_options: [plug: {Req.Test, __MODULE__}]
             )

    assert_received {:headers, headers}
    assert {"idempotency-key", "sales-invoice-email-1"} in headers
    assert {"authorization", "Bearer re_test"} in headers
  end
end

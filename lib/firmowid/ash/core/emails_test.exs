defmodule Firmowid.Ash.Core.EmailsTest do
  use ExUnit.Case, async: true

  alias Firmowid.Ash.Core.Emails

  test "confirmation and password reset emails use the shared HTML shell" do
    user = %{email: "user@example.com"}
    confirmation_url = "https://firmowid.example/confirm/token"
    reset_url = "https://firmowid.example/reset/token"

    assert {:ok, confirmation} =
             Emails.deliver_confirmation_instructions(user, confirmation_url, true)

    assert {:ok, reset} = Emails.deliver_reset_password_instructions(user, reset_url)

    for {email, url, action} <- [
          {confirmation, confirmation_url, "Potwierdź adres email"},
          {reset, reset_url, "Zresetuj hasło"}
        ] do
      assert email.html_body =~ "<!doctype html>"
      assert email.html_body =~ "alt=\"Firmowid\""
      assert email.html_body =~ action
      assert email.html_body =~ url
      assert email.html_body =~ "Pozdrawiamy,<br>Zespół Firmowid"
      assert email.text_body =~ url
    end
  end
end

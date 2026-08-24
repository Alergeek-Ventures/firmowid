defmodule Firmowid.Ash.Timetracker.LeaveRequestEmailsTest do
  use ExUnit.Case, async: true

  alias Firmowid.Ash.Timetracker.LeaveRequestEmails

  test "renders the leave request note safely while preserving line breaks" do
    leave_request = %{
      category: :absence,
      reason: :rest,
      starts_on: ~D[2026-09-01],
      ends_on: ~D[2026-09-03],
      note: "Pilne <sprawdź>\ndruga linia"
    }

    employee = %{id: Ash.UUID.generate(), name: "Jan Kowalski", email: "jan@example.com"}
    admin = %{email: "admin@example.com"}

    assert {:ok, email} =
             LeaveRequestEmails.deliver_new_leave_request([admin], leave_request, nil, employee)

    assert email.html_body =~ "<!doctype html>"
    assert email.html_body =~ "alt=\"Firmowid\""
    assert email.html_body =~ "Pilne &lt;sprawdź&gt;<br>druga linia"
    refute email.html_body =~ "&amp;lt;sprawdź&amp;gt;"
    assert email.html_body =~ "Otwórz wniosek w Firmowidzie"
    assert email.text_body =~ "Treść: Pilne <sprawdź>"
  end
end

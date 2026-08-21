defmodule Firmowid.Ash.Timetracker.LeaveRequestEmails do
  @moduledoc """
  Emails for leave/absence requests. Dispatches notifications to org admins when a new request is submitted.
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: FirmowidWeb.Core.Endpoint,
    router: FirmowidWeb.Core.Router

  import Firmowid.Mailer.Components
  import Swoosh.Email

  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Timetracker.LeaveRequest
  alias Firmowid.Mailer

  @doc """
  Notifies an admin that a new leave/absence request was submitted.
  """

  @spec deliver_new_leave_request(
          [User.t() | map()],
          LeaveRequest.t(),
          Swoosh.Attachment.t() | nil,
          User.t() | map()
        ) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_new_leave_request(admins, leave_request, attachment, employee) do
    employee_name = employee_name(employee)
    url = leave_tab_url(employee.id)
    recipients = Enum.map(admins, &to_string(&1.email))

    html = render_html(employee_name, leave_request, url)
    text = render_text(employee_name, leave_request, url)

    email =
      new()
      |> to(recipients)
      |> from({"Firmowid", "piotr@firmowid.pl"})
      |> subject("Nowy wniosek: #{employee_name}")
      |> html_body(html)
      |> text_body(text)
      |> then(fn email ->
        if attachment, do: Swoosh.Email.attachment(email, attachment), else: email
      end)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp render_html(employee_name, leave_request, url) do
    assigns = %{
      employee_name: employee_name,
      category_label: category_label(leave_request.category),
      reason_label: reason_label(leave_request.reason),
      starts_on: format_date(leave_request.starts_on),
      ends_on: format_date(leave_request.ends_on),
      note: format_note(leave_request.note),
      url: url
    }

    to_html(~H"""
    <.email preheader={"Nowy wniosek o #{@category_label}: #{@employee_name}"}>
      <.greeting>Nowy wniosek o {@category_label}</.greeting>
      <.paragraph>
        {@employee_name} złożył(a) nowy wniosek. Szczegóły poniżej - decyzję podejmiesz w Firmowidzie.
      </.paragraph>
      <.detail_row label="Pracownik" value={@employee_name} />
      <.detail_row label="Kategoria" value={@category_label} />
      <.detail_row label="Powód" value={@reason_label} />
      <.detail_row label="Okres" value={"#{@starts_on} – #{@ends_on}"} />
      <.note :if={@note != ""}>
        {@note}
      </.note>
      <.button href={@url}>Otwórz wniosek w Firmowidzie</.button>
      <.signature />
    </.email>
    """)
  end

  defp render_text(employee_name, leave_request, url) do
    """
    Nowy wniosek o #{category_label(leave_request.category)}
    Pracownik: #{employee_name}
    Powód: #{reason_label(leave_request.reason)}
    Okres: #{format_date(leave_request.starts_on)} - #{format_date(leave_request.ends_on)}
    #{note_block(leave_request.note)}Otwórz w Firmowidzie:
    #{url}
    """
  end

  defp employee_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp employee_name(%{email: email}), do: to_string(email)

  defp leave_tab_url(employee_id) do
    url(~p"/zarzadzanie/pracownicy/#{employee_id}/urlopy")
  end

  defp category_label(:leave), do: "Urlop"
  defp category_label(:absence), do: "Nieobecność"
  defp category_label(_), do: "—"

  defp reason_label(:vacation), do: "Urlop wypoczynkowy"
  defp reason_label(:sick), do: "Urlop zdrowotny"
  defp reason_label(:unpaid), do: "Urlop bezpłatny"
  defp reason_label(:indisposition), do: "Niedyspozycja"
  defp reason_label(:rest), do: "Wypoczynek"
  defp reason_label(:other), do: "Inne"
  defp reason_label(_), do: "—"

  defp format_note(note) when note in [nil, ""], do: ""

  defp format_note(note) do
    note
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace("\n", "<br>")
  end

  defp note_block(note) when note in [nil, ""], do: ""
  defp note_block(note), do: "Treść: #{note}\n\n"

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%d-%m-%Y")
  defp format_date(_), do: "—"
end

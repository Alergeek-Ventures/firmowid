defmodule Firmowid.Ash.Timetracker.LeaveRequestEmails do
  @moduledoc """
  Emails for leave/absence requests. Dispatches notifications to org admins when a new request is submitted.
  """

  import Swoosh.Email

  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Timetracker.LeaveRequest
  alias Firmowid.Mailer
  alias FirmowidWeb.Core.Endpoint

  @doc """
  Notifies an admin that a new leave/absence request was submitted.
  """

  @colors %{
    accent: "#8B3F13",
    dark: "#292929",
    grey: "#707070",
    light_grey: "#F5F5F5",
    white: "#FFFFFF"
  }

  @spec deliver_new_leave_request(
          User.t() | map(),
          LeaveRequest.t(),
          Swoosh.Attachment.t() | nil,
          User.t() | map()
        ) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_new_leave_request(admin, leave_request, employee) do
    employee_name = employee_name(employee)
    url = leave_tab_url(employee.id)

    email =
      new()
      |> to(to_string(admin.email))
      |> from({"Firmowid", "piotr@firmowid.pl"})
      |> subject("Nowy wniosek: #{employee_name}")
      |> html_body(html_body(employee_name, leave_request, url))
      |> text_body(text_body(employee_name, leave_request, url))
      |> then(fn email ->
        if attachment, do: Swoosh.Email.attachment(email, attachment), else: email
      end)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp html_body(employee_name, leave_request, url) do
    logo_url = "#{Endpoint.url()}/images/logo_firmowid.png"
    note_html = note_html(leave_request.note)

    """
    <!DOCTYPE html>
    <html lang="pl">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Nowy wniosek</title>
      <link rel="preconnect" href="https://fonts.googleapis.com">
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
      <link href="https://fonts.googleapis.com/css2?family=Lexend:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    </head>
    <body style="margin:0; padding:0; background-color: #{@colors.light_grey}; font-family:'Lexend', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; color: #{@colors.dark};">
      <table role="presentation" style="width:100%; border-collapse:collapse;">
        <tr>
          <td align="center" style="padding:40px 20px;">
            <table role="presentation" style="width:100%; max-width:640px; border-collapse:collapse; background-color: #{@colors.white}; box-shadow:0 2px 8px rgba(0,0,0,0.08);">
              <tr>
                <td style="padding:32px 40px 20px 40px; text-align:center;">
                  <img src="#{logo_url}" alt="Firmowid" style="height:40px; width:auto;">
                </td>
              </tr>
              <tr>
                <td style="padding:8px 40px 12px 40px;">
                  <h1 style="margin:0; font-size:28px; line-height:1.2; font-weight:600; color: #{@colors.dark};">
                    Nowy wniosek urlopowy
                  </h1>
                </td>
              </tr>
              <tr>
                <td style="padding:12px 40px 24px 40px;">
                  <p style="margin:0; max-width:420px; font-size:16px; line-height:1.7; color: #{@colors.grey};">
                    #{employee_name} złożył(a) nowy wniosek. Szczegóły poniżej - decyzję podejmiesz w Firmowidzie.
                  </p>
                </td>
              </tr>
              <tr>
                <td style="padding:0 40px 32px 40px;">
                  <table role="presentation" style="width:100%; border-collapse:collapse; border-top:1px solid #ECECEC;">
                    #{detail_row("Pracownik", employee_name)}
                    #{detail_row("Kategoria", category_label(leave_request.category))}
                    #{detail_row("Powód", reason_label(leave_request.reason))}
                    #{detail_row("Okres", "#{format_date(leave_request.starts_on)} – #{format_date(leave_request.ends_on)}")}
                    #{note_html}
                  </table>
                </td>
              </tr>
              <tr>
                <td align="center" style="padding:8px 40px 40px 40px;">
                  <a href="#{url}" style="display:inline-block; background-color: #{@colors.dark}; color: #{@colors.white}; text-decoration:none; padding:14px 20px; font-size:16px; font-weight:500;">
                    Otwórz wniosek w Firmowidzie
                  </a>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
    </html>
    """
  end

  defp detail_row(label, value) do
    """
    <tr>
      <td style="padding:12px 0; border-bottom:1px solid #ECECEC; width:140px; vertical-align:top; font-size:15px; color: #{@colors.grey};">
        #{label}
      </td>
      <td style="padding:12px 0; border-bottom:1px solid #ECECEC; vertical-align:top; font-size:15px; line-height:1.6; color: #{@colors.dark}; font-weight:500;">
        #{value}
      </td>
    </tr>
    """
  end

  defp note_html(note) when note in [nil, ""], do: ""

  defp note_html(note) do
    formatted =
      note
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.safe_to_string()
      |> String.replace("\n", "<br>")

    detail_row("Treść", formatted)
  end

  defp text_body(employee_name, leave_request, url) do
    """
    Nowy wniosek urlopowy / o nieobecność
    Pracownik: #{employee_name}
    Kategoria: #{category_label(leave_request.category)}
    Powód: #{reason_label(leave_request.reason)}
    Okres: #{format_date(leave_request.starts_on)} - #{format_date(leave_request.ends_on)}
    #{note_block(leave_request.note)}Otwórz w Firmowidzie:
    #{url}
    """
  end

  defp employee_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp employee_name(%{email: email}), do: to_string(email)

  defp leave_tab_url(employee_id) do
    "#{Endpoint.url()}/zarzadzanie/pracownicy/#{employee_id}/urlopy"
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

  defp note_block(note) when note in [nil, ""], do: ""
  defp note_block(note), do: "Treść: #{note}\n\n"

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%d-%m-%Y")
  defp format_date(_), do: "—"
end

defmodule Firmowid.Ash.Payroll.EmploymentContractEmails do
  @moduledoc """
  Emails for employment contract lifecycle events.

  Notifies employees about contracts awaiting signature and admins when a signed
  contract is submitted.
  """

  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: FirmowidWeb.Core.Endpoint,
    router: FirmowidWeb.Core.Router

  import Firmowid.Mailer.Components
  import Swoosh.Email

  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Payroll.UserEmploymentContract
  alias Firmowid.Mailer

  @doc """
  Notifies the employee that a new pending_signature contract awaits signing.
  """
  @spec deliver_pending_signature(User.t() | map(), UserEmploymentContract.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_pending_signature(user, contract) do
    recipient = to_string(user.email)
    url = profile_url()
    html = render_pending_signature_html(user, contract, url)
    text = render_pending_signature_text(user, contract, url)

    email =
      new()
      |> to(recipient)
      |> from({"Firmowid", "piotr@firmowid.pl"})
      |> subject("Nowa umowa do podpisu")
      |> html_body(html)
      |> text_body(text)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Notifies organization admins that an employee submitted a signed contract.
  """
  @spec deliver_signed_submitted_to_admins(
          [User.t() | map()],
          UserEmploymentContract.t(),
          User.t() | map()
        ) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_signed_submitted_to_admins(admins, contract, employee) do
    employee_name = user_name(employee)
    url = employee_profile_url(employee.id)
    recipients = Enum.map(admins, &to_string(&1.email))

    html = render_admin_signed_html(employee_name, contract, url)
    text = render_admin_signed_text(employee_name, contract, url)

    email =
      new()
      |> to(recipients)
      |> from({"Firmowid", "piotr@firmowid.pl"})
      |> subject("Podpisana umowa: #{employee_name}")
      |> html_body(html)
      |> text_body(text)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp render_pending_signature_html(user, contract, url) do
    assigns = %{
      user_name: user_name(user),
      signed_at: format_date(contract.signed_at),
      starts_at: format_date(contract.starts_at),
      contract_type: contract_type_label(contract.contract_type),
      position: contract.position || "—",
      url: url
    }

    to_html(~H"""
    <.email preheader={"Nowa umowa do podpisu · #{@signed_at}"}>
      <.greeting>Nowa umowa do podpisu</.greeting>
      <.paragraph>
        Cześć {@user_name}, w Firmowidzie czeka na Ciebie nowa umowa do podpisu.
      </.paragraph>
      <.detail_row label="Data podpisania" value={@signed_at} />
      <.detail_row label="Data rozpoczęcia" value={@starts_at} />
      <.detail_row label="Rodzaj umowy" value={@contract_type} />
      <.detail_row label="Stanowisko" value={@position} />
      <.paragraph_spaced>
        Otwórz profil, pobierz dokument i prześlij podpisaną wersję.
      </.paragraph_spaced>
      <.button href={@url}>Otwórz profil w Firmowidzie</.button>
      <.signature />
    </.email>
    """)
  end

  defp render_pending_signature_text(user, contract, url) do
    """
    Nowa umowa do podpisu
    Pracownik: #{user_name(user)}
    Data podpisania: #{format_date(contract.signed_at)}
    Data rozpoczęcia: #{format_date(contract.starts_at)}
    Rodzaj umowy: #{contract_type_label(contract.contract_type)}
    Stanowisko: #{contract.position || "—"}

    Otwórz profil w Firmowidzie:
    #{url}
    """
  end

  defp render_admin_signed_html(employee_name, contract, url) do
    assigns = %{
      employee_name: employee_name,
      signed_at: format_date(contract.signed_at),
      starts_at: format_date(contract.starts_at),
      contract_type: contract_type_label(contract.contract_type),
      position: contract.position || "—",
      url: url
    }

    to_html(~H"""
    <.email preheader={"Podpisana umowa · #{@employee_name}"}>
      <.greeting>Podpisana umowa</.greeting>
      <.paragraph>
        {@employee_name} przesłał(a) podpisaną umowę. Dokument znajdziesz w profilu pracownika.
      </.paragraph>
      <.detail_row label="Pracownik" value={@employee_name} />
      <.detail_row label="Data podpisania" value={@signed_at} />
      <.detail_row label="Data rozpoczęcia" value={@starts_at} />
      <.detail_row label="Rodzaj umowy" value={@contract_type} />
      <.detail_row label="Stanowisko" value={@position} />
      <.button href={@url}>Otwórz profil pracownika</.button>
      <.signature />
    </.email>
    """)
  end

  defp render_admin_signed_text(employee_name, contract, url) do
    """
    Podpisana umowa
    Pracownik: #{employee_name}
    Data podpisania: #{format_date(contract.signed_at)}
    Data rozpoczęcia: #{format_date(contract.starts_at)}
    Rodzaj umowy: #{contract_type_label(contract.contract_type)}
    Stanowisko: #{contract.position || "—"}

    Otwórz profil pracownika w Firmowidzie:
    #{url}
    """
  end

  defp user_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp user_name(%{email: email}), do: to_string(email)

  defp profile_url do
    url(~p"/ustawienia/profil")
  end

  defp employee_profile_url(employee_id) do
    url(~p"/zarzadzanie/pracownicy/#{employee_id}/profil")
  end

  defp contract_type_label(:uop), do: "Umowa o pracę"
  defp contract_type_label(:b2b), do: "B2B"
  defp contract_type_label(:uz), do: "Umowa zlecenie"
  defp contract_type_label(:uod), do: "Umowa o dzieło"
  defp contract_type_label(_), do: "—"

  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%d-%m-%Y")
  defp format_date(_), do: "—"
end

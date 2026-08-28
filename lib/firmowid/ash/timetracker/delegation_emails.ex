defmodule Firmowid.Ash.Timetracker.DelegationEmails do
  @moduledoc "Templated notification emails for delegation submissions."

  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: FirmowidWeb.Core.Endpoint, router: FirmowidWeb.Core.Router

  import Firmowid.Mailer.Components
  import Swoosh.Email

  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Timetracker.Delegation
  alias Firmowid.Mailer

  @spec deliver_new_delegation([User.t() | map()], Delegation.t(), User.t() | map()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_new_delegation(admins, delegation, employee) do
    name = employee_name(employee)
    url = url(~p"/zarzadzanie/pracownicy/#{employee.id}/delegacje")
    assigns = %{name: name, delegation: delegation, url: url}

    email =
      new()
      |> to(Enum.map(admins, &to_string(&1.email)))
      |> from({"Firmowid", "piotr@firmowid.pl"})
      |> subject("Nowe zgłoszenie delegacji")
      |> html_body(to_html(html(assigns)))
      |> text_body(text(assigns))

    with {:ok, _metadata} <- Mailer.deliver(email), do: {:ok, email}
  end

  defp html(assigns) do
    ~H"""
    <.email preheader="Nowe zgłoszenie delegacji">
      <.greeting>Nowe zgłoszenie delegacji</.greeting>
      <.paragraph>
        {@name} zgłosił(a) nową delegację. Szczegóły znajdziesz poniżej. Aby zatwierdzić wniosek, przejdź do Firmowida.
      </.paragraph>
      <.detail_row label="Pracownik" value={@name} />
      <.detail_row label="Data wyjazdu" value={date_range(@delegation)} />
      <.detail_row label="Cel wyjazdu" value={@delegation.purpose} />
      <.detail_row
        label="Przewidywana kwota"
        value={Money.to_string!(@delegation.advance_payment_amount)}
      />
      <.button href={@url}>Otwórz wniosek w Firmowidzie</.button>
      <.signature />
    </.email>
    """
  end

  defp text(assigns) do
    """
    Nowe zgłoszenie delegacji
    #{assigns.name} zgłosił(a) nową delegację. Szczegóły znajdziesz poniżej.
    Pracownik: #{assigns.name}
    Data wyjazdu: #{date_range(assigns.delegation)}
    Cel wyjazdu: #{assigns.delegation.purpose}
    Przewidywana kwota: #{Money.to_string!(assigns.delegation.advance_payment_amount)}

    Otwórz wniosek w Firmowidzie:
    #{assigns.url}
    """
  end

  defp employee_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp employee_name(%{email: email}), do: to_string(email)

  defp date_range(%{start_date: start_date, end_date: end_date}) do
    "#{Calendar.strftime(start_date, "%d-%m-%Y")} - #{Calendar.strftime(end_date, "%d-%m-%Y")}"
  end
end

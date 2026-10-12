defmodule Firmowid.Delegations.DelegationEmails do
  @moduledoc "Templated notification emails for delegation submissions."

  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: FirmowidWeb.Core.Endpoint, router: FirmowidWeb.Core.Router

  import Firmowid.Mailer.Components
  import Swoosh.Email

  alias Firmowid.Core.Member
  alias Firmowid.Core.User
  alias Firmowid.Delegations.Delegation
  alias Firmowid.Mailer
  alias Firmowid.TimeFormatter

  @doc "Notifies organization administrators that a signed settlement awaits review."
  @spec deliver_submitted_settlement([User.t() | map()], Delegation.t(), Member.t() | map()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_submitted_settlement(admins, delegation, employee) do
    name = employee_name(employee)
    url = url(~p"/zarzadzanie/pracownicy/#{employee.user_id}/delegacje/#{delegation.reference}")
    total = settlement_total(delegation.expenses)
    {balance_label, balance} = settlement_balance(total, delegation.advance_amount)

    assigns = %{
      name: name,
      delegation: delegation,
      url: url,
      total: total,
      balance_label: balance_label,
      balance: balance
    }

    email =
      new()
      |> to(Enum.map(admins, &to_string(&1.email)))
      |> from({"Firmowid", "piotr@firmowid.pl"})
      |> subject("Rozliczenie delegacji do rozpatrzenia")
      |> html_body(to_html(submitted_settlement_html(assigns)))
      |> text_body(submitted_settlement_text(assigns))

    with {:ok, _metadata} <- Mailer.deliver(email), do: {:ok, email}
  end

  @doc "Tells the employee that their settlement was accepted or returned for corrections."
  @spec deliver_reviewed_settlement(
          Delegation.t(),
          Member.t() | map(),
          :complete | :in_progress,
          String.t() | nil
        ) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_reviewed_settlement(delegation, employee, status, reason) do
    total = settlement_total(delegation.expenses)
    {balance_label, balance} = settlement_balance(total, delegation.advance_amount)

    assigns = %{
      name: employee_name(employee),
      delegation: delegation,
      url: url(~p"/delegacje/#{delegation.reference}"),
      subject: reviewed_subject(status),
      status: status,
      reason: reason,
      balance_label: balance_label,
      balance: balance
    }

    email =
      new()
      |> to(to_string(employee.user.email))
      |> from({"Firmowid", "piotr@firmowid.pl"})
      |> subject(assigns.subject)
      |> html_body(to_html(reviewed_settlement_html(assigns)))
      |> text_body(reviewed_settlement_text(assigns))

    with {:ok, _metadata} <- Mailer.deliver(email), do: {:ok, email}
  end

  @spec deliver_new_delegation([User.t() | map()], Delegation.t(), Member.t() | map()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_new_delegation(admins, delegation, employee) do
    name = employee_name(employee)
    url = url(~p"/zarzadzanie/pracownicy/#{employee.user_id}/delegacje")
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

  @doc "Delivers a confirmation to the employee whose delegation was approved."
  @spec deliver_approved_delegation(Delegation.t(), Member.t() | map()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_approved_delegation(delegation, employee) do
    name = employee_name(employee)
    assigns = %{name: name, delegation: delegation}

    email =
      new()
      |> to(to_string(employee.user.email))
      |> from({"Firmowid", "piotr@firmowid.pl"})
      |> subject("Delegacja została zatwierdzona")
      |> html_body(to_html(approval_html(assigns)))
      |> text_body(approval_text(assigns))

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
        value={Money.to_string!(@delegation.expected_cost)}
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
    Przewidywana kwota: #{Money.to_string!(assigns.delegation.expected_cost)}

    Otwórz wniosek w Firmowidzie:
    #{assigns.url}
    """
  end

  defp approval_html(assigns) do
    ~H"""
    <.email preheader="Delegacja została zatwierdzona">
      <.greeting>Delegacja została zatwierdzona</.greeting>
      <.paragraph>
        {@name}, Twoja delegacja została zaakceptowana.
      </.paragraph>
      <.detail_row label="Data wyjazdu" value={date_range(@delegation)} />
      <.detail_row label="Cel wyjazdu" value={@delegation.purpose} />
      <.detail_row
        label="Przewidywana kwota"
        value={Money.to_string!(@delegation.expected_cost)}
      />
      <.signature />
    </.email>
    """
  end

  defp approval_text(assigns) do
    """
    Delegacja została zatwierdzona
    #{assigns.name}, Twoja delegacja została zaakceptowana.
    Data wyjazdu: #{date_range(assigns.delegation)}
    Cel wyjazdu: #{assigns.delegation.purpose}
    Przewidywana kwota: #{Money.to_string!(assigns.delegation.expected_cost)}
    """
  end

  defp submitted_settlement_html(assigns) do
    ~H"""
    <.email preheader="Rozliczenie delegacji do rozpatrzenia">
      <.greeting>Rozliczenie delegacji do rozpatrzenia</.greeting>
      <.paragraph>
        {@name} przesłał(a) podpisane rozliczenie delegacji. Dokument oraz dowody kosztów są dostępne w Firmowidzie.
      </.paragraph>
      <.detail_row label="Pracownik" value={@name} />
      <.detail_row label="Termin" value={date_range(@delegation)} />
      <.detail_row label="Cel" value={@delegation.purpose} />
      <.detail_row label="Łączny koszt" value={Money.to_string!(@total)} />
      <.detail_row label={@balance_label} value={Money.to_string!(@balance)} />
      <.button href={@url}>Otwórz rozliczenie</.button>
      <.signature />
    </.email>
    """
  end

  defp submitted_settlement_text(assigns) do
    """
    Rozliczenie delegacji do rozpatrzenia
    #{assigns.name} przesłał(a) podpisane rozliczenie delegacji.
    Termin: #{date_range(assigns.delegation)}
    Cel: #{assigns.delegation.purpose}
    Łączny koszt: #{Money.to_string!(assigns.total)}
    #{assigns.balance_label}: #{Money.to_string!(assigns.balance)}

    Otwórz rozliczenie:
    #{assigns.url}
    """
  end

  defp reviewed_subject(:complete), do: "Rozliczenie delegacji zostało zatwierdzone"
  defp reviewed_subject(:in_progress), do: "Rozliczenie delegacji wymaga poprawek"

  defp reviewed_settlement_html(assigns) do
    ~H"""
    <.email preheader={@subject}>
      <.greeting>{@subject}</.greeting>
      <.paragraph :if={@status == :complete}>
        {@name}, pracodawca zatwierdził Twoje rozliczenie delegacji.
      </.paragraph>
      <.paragraph :if={@status == :in_progress}>
        {@name}, pracodawca zwrócił Twoje rozliczenie delegacji do poprawy.
      </.paragraph>
      <.detail_row label="Termin" value={date_range(@delegation)} />
      <.detail_row label="Cel" value={@delegation.purpose} />
      <.detail_row
        :if={@status == :complete}
        label={@balance_label}
        value={Money.to_string!(@balance)}
      />
      <.detail_row
        :if={@status == :in_progress}
        label="Uwagi"
        value={@reason}
      />
      <.button href={@url}>Otwórz rozliczenie</.button>
      <.signature />
    </.email>
    """
  end

  defp reviewed_settlement_text(%{status: :complete} = assigns) do
    """
    #{assigns.subject}
    #{assigns.name}, pracodawca zatwierdził Twoje rozliczenie delegacji.
    Termin: #{date_range(assigns.delegation)}
    Cel: #{assigns.delegation.purpose}
    #{assigns.balance_label}: #{Money.to_string!(assigns.balance)}

    Otwórz rozliczenie:
    #{assigns.url}
    """
  end

  defp reviewed_settlement_text(%{status: :in_progress} = assigns) do
    """
    #{assigns.subject}
    #{assigns.name}, pracodawca zwrócił Twoje rozliczenie delegacji do poprawy.
    Termin: #{date_range(assigns.delegation)}
    Cel: #{assigns.delegation.purpose}
    Uwagi: #{assigns.reason}

    Otwórz rozliczenie:
    #{assigns.url}
    """
  end

  defp settlement_total(expenses) do
    Enum.reduce(expenses, Money.new(:PLN, 0), fn expense, total ->
      amount = expense.settlement_amount || expense.expense_amount
      Money.add!(total, amount)
    end)
  end

  defp settlement_balance(total, advance) do
    if Money.compare(total, advance) in [:gt, :eq],
      do: {"Do wypłaty pracownikowi", Money.sub!(total, advance)},
      else: {"Do zwrotu przez pracownika", Money.sub!(advance, total)}
  end

  defp employee_name(%{name: name}) when is_binary(name) and name != "", do: name
  defp employee_name(%{user: %{email: email}}), do: to_string(email)

  defp date_range(%{start_date: start_date, end_date: end_date}) do
    TimeFormatter.format_date_range(start_date, end_date)
  end
end

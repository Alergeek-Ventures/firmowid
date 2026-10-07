defmodule Firmowid.Analytics do
  @moduledoc """
  Captures allowlisted server-side events and synchronizes user identity in PostHog.

  Uses stable user/organization IDs and approved properties. Identity sync explicitly
  permits the current account email for person profiles and flag management.
  Browser consent controls browser telemetry separately; server-side events do not
  use cookies.
  """

  @event_names %{
    invoice_created: "invoice_created",
    bank_connection_completed: "bank_connection_completed",
    time_entry_created: "time_entry_created",
    payroll_rates_updated: "payroll_rates_updated",
    counterparty_created: "counterparty_created",
    counterparty_updated: "counterparty_updated"
  }

  @doc "Synchronizes the current account email to its PostHog person profile, independently of browser consent."
  @spec identify_user(map() | nil) :: :ok
  def identify_user(%{id: user_id, email: email}) when not is_nil(user_id) and not is_nil(email) do
    if Application.get_env(:posthog, :enable, false) and enabled?() do
      # This SDK has no identify helper; its capture API supports PostHog's
      # $identify/$set protocol without changing the business-event allowlist.
      PostHog.bare_capture("$identify", to_string(user_id), %{
        "$set" => %{"email" => to_string(email)}
      })
    end

    :ok
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  def identify_user(_user), do: :ok

  @doc "Captures an allowlisted organization-scoped event, ignoring invalid inputs or telemetry failures."
  @spec capture_business_event(atom(), term(), term(), map()) :: :ok
  def capture_business_event(event, user_id, organization_id, properties \\ %{})

  def capture_business_event(event, user_id, organization_id, properties)
      when is_atom(event) and not is_nil(user_id) and not is_nil(organization_id) and is_map(properties) do
    with {:ok, event_name} <- Map.fetch(@event_names, event),
         {:ok, safe_properties} <- validate_properties(event, properties),
         true <- enabled?() do
      properties =
        Map.put(safe_properties, "$groups", %{"organization" => to_string(organization_id)})

      PostHog.bare_capture(event_name, to_string(user_id), properties)
    end

    :ok
  rescue
    _ -> :ok
  end

  def capture_business_event(_event, _user_id, _organization_id, _properties), do: :ok

  @doc "Captures a successful password or Google account registration, without requiring an organization."
  @spec capture_account_created(map(), :password | :google) :: :ok
  def capture_account_created(%{id: user_id}, method) when not is_nil(user_id) and method in [:password, :google] do
    if enabled?() do
      PostHog.bare_capture("account_created", to_string(user_id), %{
        "method" => Atom.to_string(method)
      })
    end

    :ok
  rescue
    _ -> :ok
  end

  def capture_account_created(_user, _method), do: :ok

  defp enabled? do
    match?(%{enabled: true}, PostHog.config())
  rescue
    _ -> false
  end

  defp validate_properties(event, properties)
       when event in [
              :invoice_created,
              :bank_connection_completed,
              :time_entry_created,
              :counterparty_created,
              :counterparty_updated
            ] do
    if properties == %{}, do: {:ok, %{}}, else: :error
  end

  defp validate_properties(:payroll_rates_updated, %{changed_employee_count: count})
       when is_integer(count) and count >= 0, do: {:ok, %{"changed_employee_count" => count}}

  defp validate_properties(_event, _properties), do: :error
end

defmodule Firmowid.Analytics do
  @moduledoc """
  Captures allowlisted server-side events and synchronizes user identity in PostHog.

  Uses stable user/organization IDs and approved properties. Identity sync explicitly
  permits the current account email for person profiles and flag management.
  Browser consent controls browser telemetry separately; server-side events do not
  use cookies.

  Business events carry only allowlisted properties. The one exception is the feedback
  survey response (`capture_feedback/4`): it carries the free text the user chose to
  send through the feedback form.
  """

  alias Firmowid.Core
  alias Firmowid.Core.User

  @event_names %{
    invoice_created: "invoice_created",
    sales_invoice_creator_opened: "sales_invoice_creator_opened",
    sales_invoice_edit_opened: "sales_invoice_edit_opened",
    sales_invoice_correction_opened: "sales_invoice_correction_opened",
    ksef_fetch_requested: "ksef_fetch_requested",
    ksef_skipped_sales_invoices_banner_viewed: "ksef_skipped_sales_invoices_banner_viewed",
    bank_connection_completed: "bank_connection_completed",
    time_entry_created: "time_entry_created",
    payroll_rates_updated: "payroll_rates_updated",
    counterparty_created: "counterparty_created",
    counterparty_updated: "counterparty_updated",
    onboarding_completed: "onboarding_completed",
    leave_request_created: "leave_request_created",
    delegation_created: "delegation_created"
  }

  # Where the owner finishing the onboarding heard about Firmowid.
  @heard_from_sources [
    :search,
    :ai_assistant,
    :recommendation,
    :accountant,
    :social_media,
    :other
  ]

  @doc """
  Synchronizes the current account email to its PostHog person profile, independently of browser consent.

  A superuser's session as the account (see `Firmowid.Core.impersonator_id/1`) is not synchronized.
  """
  @spec identify_user(map() | nil) :: :ok
  def identify_user(%{id: user_id, email: email} = user) when not is_nil(user_id) and not is_nil(email) do
    if Application.get_env(:posthog, :enable, false) and enabled?() and not impersonated?(user) do
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

  @doc """
  Captures an allowlisted organization-scoped event of the acting user, ignoring invalid
  inputs or telemetry failures.

  Nothing is captured in a superuser's session as the user (see `Firmowid.Core.impersonator_id/1`).
  """
  @spec capture_business_event(atom(), term(), term(), map()) :: :ok
  def capture_business_event(event, actor, organization_id, properties \\ %{})

  def capture_business_event(event, %User{id: user_id} = actor, organization_id, properties)
      when is_atom(event) and not is_nil(organization_id) and is_map(properties) do
    with {:ok, event_name} <- Map.fetch(@event_names, event),
         {:ok, safe_properties} <- validate_properties(event, properties),
         false <- impersonated?(actor),
         true <- enabled?() do
      properties =
        safe_properties
        |> Map.merge(%{"surface" => "app", "auth_state" => "identified"})
        |> Map.put("$groups", %{"organization" => to_string(organization_id)})

      PostHog.bare_capture(event_name, to_string(user_id), properties)
    end

    :ok
  rescue
    _ -> :ok
  end

  def capture_business_event(_event, _actor, _organization_id, _properties), do: :ok

  # The PostHog survey (type "api", shown to nobody) that collects in-app feedback.
  @feedback_survey_id "01a1d00b-c733-0000-a5bd-01cd8267cb42"
  @feedback_question_id "0860110e-5940-4660-9cad-6dd33cf7a11a"
  @feedback_question "Jak możemy usprawnić Firmowida?"

  @doc """
  Captures the text a user sent through the feedback form as a response to the PostHog
  feedback survey.

  Unlike business events, this one carries free text the user chose to send. Every call
  is a new response (the form can be used any number of times). Nothing is captured in a
  superuser's session as the user (see `Firmowid.Core.impersonator_id/1`).
  """
  @spec capture_feedback(term(), term(), String.t(), String.t()) :: :ok
  def capture_feedback(%User{id: user_id} = actor, organization_id, page_path, content)
      when not is_nil(organization_id) and is_binary(page_path) and is_binary(content) do
    with false <- impersonated?(actor),
         true <- enabled?() do
      properties = %{
        "$survey_id" => @feedback_survey_id,
        "$survey_submission_id" => Ash.UUID.generate(),
        "$survey_completed" => true,
        "$survey_questions" => [%{id: @feedback_question_id, question: @feedback_question}],
        "$survey_response_#{@feedback_question_id}" => content,
        "page_path" => page_path,
        "surface" => "app",
        "auth_state" => "identified",
        "$groups" => %{"organization" => to_string(organization_id)}
      }

      PostHog.bare_capture("survey sent", to_string(user_id), properties)
    end

    :ok
  rescue
    _ -> :ok
  end

  def capture_feedback(_actor, _organization_id, _page_path, _content), do: :ok

  @doc "Captures a successful password or Google account registration, without requiring an organization."
  @spec capture_account_created(map(), :password | :google) :: :ok
  def capture_account_created(%{id: user_id}, method) when not is_nil(user_id) and method in [:password, :google] do
    capture_account_event("account_created", user_id, method)
  end

  def capture_account_created(_user, _method), do: :ok

  @doc "Captures a successful sign-in after account access has been granted."
  @spec capture_user_signed_in(map(), :password | :google) :: :ok
  def capture_user_signed_in(%{id: user_id} = user, method) when not is_nil(user_id) and method in [:password, :google] do
    groups =
      case user do
        %{member: %{organization_id: organization_id}} ->
          %{"$groups" => %{"organization" => to_string(organization_id)}}

        _user ->
          %{}
      end

    capture_account_event("user_signed_in", user_id, method, groups)
  end

  def capture_user_signed_in(_user, _method), do: :ok

  defp capture_account_event(event, user_id, method, properties \\ %{}) do
    if enabled?() do
      properties =
        Map.merge(properties, %{
          "method" => Atom.to_string(method),
          "surface" => "app",
          "auth_state" => "identified"
        })

      PostHog.bare_capture(event, to_string(user_id), properties)
    end

    :ok
  rescue
    _ -> :ok
  end

  defp impersonated?(%User{} = user), do: not is_nil(Core.impersonator_id(user))
  defp impersonated?(_user), do: false

  defp enabled? do
    match?(%{enabled: true}, PostHog.config())
  rescue
    _ -> false
  end

  defp validate_properties(event, properties)
       when event in [
              :invoice_created,
              :sales_invoice_creator_opened,
              :sales_invoice_edit_opened,
              :sales_invoice_correction_opened,
              :bank_connection_completed,
              :time_entry_created,
              :counterparty_created,
              :counterparty_updated,
              :leave_request_created,
              :delegation_created
            ] do
    if properties == %{}, do: {:ok, %{}}, else: :error
  end

  defp validate_properties(:onboarding_completed, %{heard_from: source}) when source in @heard_from_sources,
    do: {:ok, %{"heard_from" => Atom.to_string(source)}}

  defp validate_properties(:onboarding_completed, properties) when properties == %{}, do: {:ok, %{}}

  defp validate_properties(:payroll_rates_updated, %{changed_employee_count: count})
       when is_integer(count) and count >= 0, do: {:ok, %{"changed_employee_count" => count}}

  defp validate_properties(:ksef_fetch_requested, %{already_fetching: fetching?}) when is_boolean(fetching?),
    do: {:ok, %{"already_fetching" => fetching?}}

  defp validate_properties(:ksef_skipped_sales_invoices_banner_viewed, %{skipped_invoice_count: count})
       when is_integer(count) and count > 0, do: {:ok, %{"skipped_invoice_count" => count}}

  defp validate_properties(_event, _properties), do: :error
end

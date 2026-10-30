defmodule FirmowidWeb.Infrastructure.Flags do
  @moduledoc """
  Server-side feature flag helpers backed by PostHog.

  Feature flags are evaluated once per authenticated LiveView mount and assigned
  under `:feature_flags`. Templates then call `flag_enabled?/2` against assigns,
  which keeps render-time checks fast and side-effect free.

  Imported automatically via `html_helpers/0`, so every LiveView,
  LiveComponent and HTML module can call `flag_enabled?/2` directly.

  ## Usage in templates

      <%= if flag_enabled?(:analysis_dashboard, assigns) do %>
        <.link navigate={~p"/analiza"}>Analiza</.link>
      <% end %>

  Development enables every flag. Elsewhere missing flags default to `false`.
  """

  alias Firmowid.Core
  alias Firmowid.Core.User
  alias Firmowid.ErrorKind
  alias PostHog.FeatureFlags
  alias PostHog.FeatureFlags.Evaluations
  alias PostHog.FeatureFlags.Result

  require Logger

  @flag_keys %{
    accurate_salary_calculation: "accurate_salary_calculation",
    analysis_dashboard: "analysis_dashboard",
    delegations: "delegations",
    tax_prognosis: "tax_prognosis"
  }

  @doc """
  Evaluates all supported feature flags for the given user.

  Returns a map keyed by local atom names, defaulting every flag to `false` when
  PostHog is disabled or the evaluation fails.
  """
  @spec evaluate_for_user(map() | nil) :: %{optional(atom()) => boolean()}
  def evaluate_for_user(nil), do: empty_flags()

  def evaluate_for_user(user) when is_map(user) do
    if development?() do
      Map.new(@flag_keys, fn {key, _} -> {key, true} end)
    else
      evaluate_posthog_flags(user)
    end
  end

  defp evaluate_posthog_flags(user) do
    if posthog_enabled?() do
      user
      |> evaluation_payload()
      |> FeatureFlags.evaluate_flags()
      |> case do
        {:ok, snapshot} ->
          resolve_flags(snapshot, impersonated?(user))

        {:error, error} ->
          Logger.warning("PostHog feature flag evaluation failed",
            error_kind: ErrorKind.classify(error)
          )

          empty_flags()
      end
    else
      empty_flags()
    end
  end

  @doc """
  Returns `true` when `flag_name` is enabled in the given assigns.

  Always returns `true` in development; elsewhere missing flags return `false`.
  """
  @spec flag_enabled?(atom(), map()) :: boolean()
  def flag_enabled?(flag_name, %{feature_flags: feature_flags}) when is_atom(flag_name) do
    development?() or Map.get(feature_flags, flag_name, false)
  end

  def flag_enabled?(flag_name, _assigns) when is_atom(flag_name), do: development?()

  defp development?, do: Application.get_env(:firmowid, :environment) == :dev

  @doc """
  Returns an empty `:feature_flags` map with all supported flags set to `false`.
  """
  @spec empty_flags() :: %{optional(atom()) => boolean()}
  def empty_flags do
    Map.new(@flag_keys, fn {flag_name, _posthog_key} -> {flag_name, false} end)
  end

  @doc """
  Returns the PostHog flag keys requested by this app.
  """
  @spec requested_flag_keys() :: [String.t()]
  def requested_flag_keys do
    Map.values(@flag_keys)
  end

  defp resolve_flags(snapshot, impersonated?) do
    Enum.reduce(@flag_keys, empty_flags(), fn {flag_name, posthog_key}, flags ->
      Map.put(flags, flag_name, flag_enabled_in?(snapshot, posthog_key, impersonated?))
    end)
  end

  # `Evaluations.enabled?/2` reports a `$feature_flag_called` event, which a
  # superuser's session as the user must not add to the user's analytics.
  defp flag_enabled_in?(snapshot, posthog_key, false), do: Evaluations.enabled?(snapshot, posthog_key)

  defp flag_enabled_in?(%Evaluations{flags: flags}, posthog_key, true),
    do: match?({:ok, %Result{enabled: true}}, Map.fetch(flags, posthog_key))

  defp impersonated?(%User{} = user), do: not is_nil(Core.impersonator_id(user))
  defp impersonated?(_user), do: false

  defp evaluation_payload(user) do
    %{
      distinct_id: to_string(Map.fetch!(user, :id)),
      person_properties: person_properties(user),
      flag_keys: requested_flag_keys()
    }
  end

  defp person_properties(user) do
    user
    |> Map.take([:email])
    |> Map.put(:organization_id, member_organization_id(user))
    |> Map.put(:role, member_role(user))
    |> Map.new(fn
      {:email, email} -> {:email, email && to_string(email)}
      {:role, role} -> {:role, role && to_string(role)}
      entry -> entry
    end)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp member_role(%{member: %{role: role}}), do: role
  defp member_role(_user), do: nil

  defp member_organization_id(%{member: %{organization_id: organization_id}}), do: organization_id
  defp member_organization_id(_user), do: nil

  defp posthog_enabled? do
    Application.get_env(:posthog, :enable, false)
  end
end

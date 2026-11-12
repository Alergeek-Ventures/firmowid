defmodule FirmowidWeb.Infrastructure.Flags do
  @moduledoc """
  Server-side feature flag helpers backed by PostHog.

  Feature flags are assigned under `:feature_flags` on every authenticated
  LiveView mount; their evaluation by PostHog is kept for a few minutes per user,
  organization and role, so a mount does not wait for it each time. Templates then
  call `flag_enabled?/2` against assigns, which keeps render-time checks fast and
  side-effect free.

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
    inbox: "inbox"
  }

  @cache :feature_flags

  # Flags change rarely, and a mount must not wait for PostHog every time.
  @cache_expire to_timeout(minute: 5)

  @doc """
  Evaluates all supported feature flags for the given user.

  Returns a map keyed by local atom names, defaulting every flag to `false` when
  the evaluation fails; without PostHog only `:enabled_feature_flags` from the
  configuration are on.
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
    if posthog_enabled?(), do: cached_flags(user), else: offline_flags()
  end

  # What the evaluation sends about the user identifies its result. A failed
  # evaluation is not kept; the next mount asks again.
  defp cached_flags(user) do
    payload = evaluation_payload(user)
    key = {payload.distinct_id, payload.person_properties}

    case Cachex.get(@cache, key) do
      {:ok, nil} -> request_flags(payload, key, impersonated?(user))
      {:ok, flags} -> flags
    end
  end

  defp request_flags(payload, key, impersonated?) do
    case FeatureFlags.evaluate_flags(payload) do
      {:ok, snapshot} ->
        flags = resolve_flags(snapshot, impersonated?)

        # PostHog also answers when it could compute only some of the flags.
        if not snapshot.errors_while_computing do
          Cachex.put(@cache, key, flags, expire: @cache_expire)
        end

        flags

      {:error, error} ->
        Logger.warning("PostHog feature flag evaluation failed",
          error_kind: ErrorKind.classify(error)
        )

        empty_flags()
    end
  end

  # Without PostHog (tests) only the flags the configuration enables are on, so a
  # test can cover a flagged feature while the others stay off as in production.
  defp offline_flags do
    enabled = Application.get_env(:firmowid, :enabled_feature_flags, [])
    Map.new(@flag_keys, fn {flag_name, _posthog_key} -> {flag_name, flag_name in enabled} end)
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

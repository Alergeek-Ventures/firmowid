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

  Missing flags always default to `false`.
  """

  alias PostHog.FeatureFlags
  alias PostHog.FeatureFlags.Evaluations

  require Logger

  @flag_keys %{
    analysis_dashboard: "analysis_dashboard"
  }

  @doc """
  Evaluates all supported feature flags for the given user.

  Returns a map keyed by local atom names, defaulting every flag to `false` when
  PostHog is disabled or the evaluation fails.
  """
  @spec evaluate_for_user(map() | nil) :: %{optional(atom()) => boolean()}
  def evaluate_for_user(nil), do: empty_flags()

  def evaluate_for_user(user) when is_map(user) do
    if posthog_enabled?() do
      user
      |> evaluation_payload()
      |> FeatureFlags.evaluate_flags()
      |> case do
        {:ok, snapshot} ->
          resolve_flags(snapshot)

        {:error, error} ->
          Logger.warning("PostHog feature flag evaluation failed: #{inspect(error)}")
          empty_flags()
      end
    else
      empty_flags()
    end
  end

  @doc """
  Returns `true` when `flag_name` is enabled in the given assigns.

  Safely returns `false` when the assigns do not contain a `:feature_flags` map
  or when the flag does not exist.
  """
  @spec flag_enabled?(atom(), map()) :: boolean()
  def flag_enabled?(flag_name, %{feature_flags: feature_flags}) when is_atom(flag_name) do
    Map.get(feature_flags, flag_name, false)
  end

  def flag_enabled?(flag_name, _assigns) when is_atom(flag_name), do: false

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

  defp resolve_flags(snapshot) do
    Enum.reduce(@flag_keys, empty_flags(), fn {flag_name, posthog_key}, flags ->
      Map.put(flags, flag_name, Evaluations.enabled?(snapshot, posthog_key))
    end)
  end

  defp evaluation_payload(user) do
    %{
      distinct_id: to_string(Map.fetch!(user, :id)),
      person_properties: person_properties(user),
      flag_keys: requested_flag_keys()
    }
  end

  defp person_properties(user) do
    user
    |> Map.take([:email, :organization_id, :role])
    |> Map.new(fn
      {:role, role} -> {:role, role && to_string(role)}
      entry -> entry
    end)
    |> Map.put(:email_domain, email_domain(user))
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp email_domain(%{email: email}) when is_binary(email) do
    case String.split(email, "@", parts: 2) do
      [_local_part, domain] when domain != "" -> domain
      _ -> nil
    end
  end

  defp email_domain(_user), do: nil

  defp posthog_enabled? do
    Application.get_env(:posthog, :enable, false)
  end
end

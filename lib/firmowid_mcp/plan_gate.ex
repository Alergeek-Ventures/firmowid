defmodule FirmowidMcp.PlanGate do
  @moduledoc """
  Refuses every tool call of an organization whose billing plan does not include
  AI clients, with a sentence the model relays to the person. The connection stays
  valid, so it works again as soon as the organization buys a plan. The plan rule
  is `Firmowid.Billing.PlanCatalog`.
  """

  alias Firmowid.Billing.PlanCatalog
  alias FirmowidMcp.Invoicing.Privacy
  alias FirmowidWeb.Billing.Utilities.Worksheet
  alias FirmowidWeb.Settings.Utilities.Navigation, as: SettingsNavigation

  @doc """
  The router's `tool_argument_transformer`: refuses the call when the actor's
  organization plan lacks the AI feature, otherwise validates the arguments.
  """
  @spec tool_arguments(%AshAi.Tool{}, map(), map()) :: {:ok, map()} | {:error, String.t()}
  def tool_arguments(tool, arguments, %{actor: actor} = context) do
    case refusal(actor) do
      nil -> Privacy.validate_arguments(tool, arguments, context)
      refusal -> {:error, refusal}
    end
  end

  @doc """
  Returns the sentence that refuses the actor's tool calls, or `nil` when the
  plan of the actor's organization includes AI clients.
  """
  @spec refusal(Firmowid.Core.User.t()) :: String.t() | nil
  def refusal(%{member: %{organization: %{billing_plan: plan}}}) do
    if not PlanCatalog.includes?(plan, :ai), do: refusal_text()
  end

  defp refusal_text do
    plan =
      Gettext.with_locale(Firmowid.Gettext, "en", fn ->
        :ai |> PlanCatalog.plan_with() |> Worksheet.plan_label()
      end)

    "This company's Firmowid plan does not include AI clients, so no tool can be used. " <>
      "Tell the user that connecting AI clients is available in the #{plan} plan, " <>
      "and that the company owner can change the plan at #{subscription_url()}."
  end

  defp subscription_url, do: FirmowidMcp.endpoint().url() <> SettingsNavigation.canonical_path(:subscription)
end

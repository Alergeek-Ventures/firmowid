defmodule Firmowid.Ash.Analysis.Workers.CategoryWorker do
  @moduledoc """
  Classifies a year's entries still waiting for a category, or with `refresh`
  re-suggests the classifier's suggestions after the owner corrected one.
  Uniqueness is set where jobs are queued, in `Analysis.classify_categories_later/3`.
  """
  use Oban.Worker, queue: :analysis_classification, max_attempts: 3

  alias Firmowid.Ash.Analysis.Services.CategoryClassifier
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Scope

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    tenant = args["organization_id"]
    actor = Core.load_member(%User{id: args["user_id"]}, tenant)
    scope = %Scope{actor: actor, tenant: tenant}

    with {:ok, user} <- User.get(args["user_id"], scope: scope),
         {:ok, scope} <- Scope.new(Core.load_member(user, tenant), tenant),
         :ok <- CategoryClassifier.classify(args["year"], args["refresh"], scope) do
      :ok
    else
      {:error, :actor_tenant_mismatch} -> {:cancel, :actor_tenant_mismatch}
      {:error, %Ash.Error.Forbidden{} = error} -> {:cancel, error}
      {:error, reason} -> {:error, reason}
    end
  end
end

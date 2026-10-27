defmodule Firmowid.Ash.Analysis.Workers.CategoryWorker do
  @moduledoc """
  Classifies a year's entries still waiting for a category, or with `refresh`
  re-suggests the classifier's suggestions after the owner corrected one.
  Uniqueness is set where jobs are queued, in `Analysis.classify_categories_later/3`.
  """
  use Oban.Worker, queue: :analysis_classification, max_attempts: 3

  alias Firmowid.Ash.Analysis
  alias Firmowid.Ash.Analysis.Services.CategoryClassifier

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    CategoryClassifier.classify(
      args["year"],
      args["refresh"],
      Analysis.classifier_scope(args["organization_id"])
    )
  end
end

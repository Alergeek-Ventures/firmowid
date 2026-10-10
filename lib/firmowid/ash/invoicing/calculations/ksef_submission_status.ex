defmodule Firmowid.Ash.Invoicing.Calculations.KsefSubmissionStatus do
  @moduledoc """
  Calculates sales invoice KSeF submission status using the domain's submission
  rules and a single batch query for the latest Oban jobs.
  """

  use Ash.Resource.Calculation

  alias Ash.Resource.Calculation.Context
  alias Firmowid.Ash.Ksef
  alias Firmowid.Ash.Ksef.SubmissionInfo

  @doc "Loads the invoice fields required by the shared submission information rules."
  @spec load(Ash.Query.t(), keyword(), Context.t()) :: [atom()]
  @impl true
  def load(_query, _opts, _context) do
    [:id, :ksef_number, :ksef_session_reference_number, :locked_at]
  end

  @doc "Returns a submission status for each invoice in the supplied order."
  @spec calculate([map()], keyword(), Context.t()) :: [
          SubmissionInfo.status()
        ]
  @impl true
  def calculate(records, _opts, _context) do
    records
    |> Ksef.get_submission_infos()
    |> Enum.map(& &1.status)
  end
end

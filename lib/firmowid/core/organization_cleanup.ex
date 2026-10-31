defmodule Firmowid.Core.OrganizationCleanup do
  @moduledoc """
  Local cleanup through authorized Ash resource interfaces.

  The caller must authorize parent deletion before constructing a cleanup scope.
  Database cleanup runs inside the parent's transaction; ETS wizard cleanup runs
  after it commits. Each resource restricts the cleanup role to named actions and
  records matching its organization/user.
  """

  alias Ash.BulkResult
  alias Firmowid.Analysis.TagDefinition
  alias Firmowid.Billing.Snapshot
  alias Firmowid.Core.Member
  alias Firmowid.Core.OauthAuthorizationCode
  alias Firmowid.Core.OauthConsent
  alias Firmowid.Core.OauthRefreshToken
  alias Firmowid.Invoicing.KsefInvoiceDigest
  alias Firmowid.Invoicing.KsefInvoiceDigestItem
  alias Firmowid.Invoicing.SalesInvoiceEmailDelivery
  alias Firmowid.Invoicing.SkippedKsefSalesInvoice
  alias Firmowid.Invoicing.WizardState
  alias Firmowid.Payroll.UserEmploymentContract
  alias Firmowid.Payroll.UserSalary
  alias Firmowid.Scope
  alias Firmowid.Timetracker.LeaveRequest
  alias Firmowid.Timetracker.Project
  alias Firmowid.Timetracker.Session

  @doc "Remove restrictive organization dependents, explicitly deleting children first."
  @spec remove_dependents(Scope.t()) :: :ok | {:error, term()}
  def remove_dependents(scope) do
    with :ok <- destroy_records(Snapshot.list(%{}, scope: scope), &Snapshot.destroy/2, scope),
         :ok <-
           destroy_records(
             KsefInvoiceDigestItem.read(%{}, scope: scope),
             &KsefInvoiceDigestItem.destroy/2,
             scope
           ),
         :ok <- destroy_records(UserSalary.list(%{}, scope: scope), &UserSalary.destroy/2, scope),
         :ok <-
           destroy_records(
             KsefInvoiceDigest.list(%{}, scope: scope),
             &KsefInvoiceDigest.destroy/2,
             scope
           ),
         :ok <-
           destroy_records(LeaveRequest.list(%{}, scope: scope), &LeaveRequest.destroy/2, scope),
         :ok <-
           destroy_records(
             UserEmploymentContract.list(%{}, scope: scope),
             &UserEmploymentContract.destroy/2,
             scope
           ),
         :ok <-
           destroy_records(
             SalesInvoiceEmailDelivery.list(%{}, scope: scope),
             &SalesInvoiceEmailDelivery.destroy/2,
             scope
           ),
         :ok <-
           destroy_records(
             SkippedKsefSalesInvoice.list(%{}, scope: scope),
             &SkippedKsefSalesInvoice.destroy/2,
             scope
           ),
         :ok <-
           destroy_records(
             Firmowid.Timetracker.list_sessions(%{}, scope: scope),
             &Session.destroy/2,
             scope
           ),
         :ok <- destroy_records(Project.list(%{}, scope: scope), &Project.destroy/2, scope) do
      # Project.destroy removes linked tags through its normal lifecycle. Only
      # fetch the remaining standalone tags after every project has been deleted.
      destroy_records(
        TagDefinition.list_tag_definitions(%{}, scope: scope),
        &TagDefinition.destroy/2,
        scope
      )
    end
  end

  @doc "Remove all memberships, which detaches the accounts without deleting them."
  @spec detach_users(Scope.t()) :: :ok | {:error, term()}
  def detach_users(scope) do
    destroy_records(Member.list(scope: scope), &Member.destroy/2, scope)
  end

  @doc "Removes ephemeral wizard data only after the organization's database deletion succeeds."
  @spec remove_wizard_states(Scope.t()) :: :ok | {:error, term()}
  def remove_wizard_states(scope) do
    # Include orphaned items; the normal parent action retains its cascade.
    Enum.reduce_while([WizardState.Item, WizardState], :ok, fn resource, :ok ->
      case Ash.bulk_destroy(resource, :destroy, %{},
             scope: scope,
             strategy: [:atomic],
             return_errors?: true,
             stop_on_error?: true
           ) do
        %BulkResult{status: :success} -> {:cont, :ok}
        %BulkResult{errors: errors} -> {:halt, {:error, Ash.Error.to_error_class(errors)}}
      end
    end)
  end

  @doc "Remove only the actual deleted account's OAuth dependents, even without an organization."
  @spec remove_account_oauth_dependents(Scope.t()) :: :ok | {:error, term()}
  def remove_account_oauth_dependents(scope) do
    args = %{user_id: scope.actor.user_id}

    with :ok <-
           destroy_records(
             OauthAuthorizationCode.list(args, scope: scope),
             &OauthAuthorizationCode.destroy/2,
             scope
           ),
         :ok <-
           destroy_records(OauthConsent.list(args, scope: scope), &OauthConsent.destroy/2, scope) do
      destroy_records(
        OauthRefreshToken.list(args, scope: scope),
        &OauthRefreshToken.destroy/2,
        scope
      )
    end
  end

  defp destroy_records({:ok, records}, destroy, scope) do
    each(records, &destroy.(&1, scope: scope))
  end

  defp destroy_records({:error, error}, _destroy, _scope), do: {:error, error}

  defp each(records, operation) do
    Enum.reduce_while(records, :ok, fn record, :ok ->
      case operation.(record) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end

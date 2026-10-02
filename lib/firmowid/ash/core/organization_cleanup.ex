defmodule Firmowid.Ash.Core.OrganizationCleanup do
  @moduledoc """
  Local cleanup through authorized Ash resource interfaces.

  The caller must authorize parent deletion before constructing a cleanup scope.
  Run these operations inside the parent's transaction. Each resource restricts
  the cleanup role to named actions and records matching its organization/user.
  """

  alias Firmowid.Ash.Analysis.TagDefinition
  alias Firmowid.Ash.Assistant.Session, as: AssistantSession
  alias Firmowid.Ash.Billing.Snapshot
  alias Firmowid.Ash.Core
  alias Firmowid.Ash.Core.OauthAuthorizationCode
  alias Firmowid.Ash.Core.OauthConsent
  alias Firmowid.Ash.Core.OauthRefreshToken
  alias Firmowid.Ash.Core.User
  alias Firmowid.Ash.Invoicing.KsefInvoiceDigest
  alias Firmowid.Ash.Invoicing.KsefInvoiceDigestItem
  alias Firmowid.Ash.Invoicing.SalesInvoiceEmailDelivery
  alias Firmowid.Ash.Payroll.UserEmploymentContract
  alias Firmowid.Ash.Payroll.UserSalary
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker.LeaveRequest
  alias Firmowid.Ash.Timetracker.Project
  alias Firmowid.Ash.Timetracker.Session

  @doc "Remove restrictive organization dependents, explicitly deleting children first."
  @spec remove_dependents(Scope.t()) :: :ok | {:error, term()}
  def remove_dependents(scope) do
    with :ok <-
           destroy_records(
             AssistantSession.read(%{}, scope: scope),
             &AssistantSession.destroy/2,
             scope
           ),
         :ok <- destroy_records(Snapshot.read(%{}, scope: scope), &Snapshot.destroy/2, scope),
         :ok <-
           destroy_records(
             KsefInvoiceDigestItem.read(%{}, scope: scope),
             &KsefInvoiceDigestItem.destroy/2,
             scope
           ),
         :ok <- destroy_records(UserSalary.read(%{}, scope: scope), &UserSalary.destroy/2, scope),
         :ok <-
           destroy_records(
             KsefInvoiceDigest.read(%{}, scope: scope),
             &KsefInvoiceDigest.destroy/2,
             scope
           ),
         :ok <-
           destroy_records(LeaveRequest.read(%{}, scope: scope), &LeaveRequest.destroy/2, scope),
         :ok <-
           destroy_records(
             UserEmploymentContract.read(%{}, scope: scope),
             &UserEmploymentContract.destroy/2,
             scope
           ),
         :ok <-
           destroy_records(
             SalesInvoiceEmailDelivery.read(%{}, scope: scope),
             &SalesInvoiceEmailDelivery.destroy/2,
             scope
           ),
         :ok <-
           destroy_records(
             Firmowid.Ash.Timetracker.list_sessions(%{}, scope: scope),
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

  @doc "Detach all organization accounts and avatar references without deleting the accounts."
  @spec detach_users(Scope.t()) :: :ok | {:error, term()}
  def detach_users(scope) do
    case Core.list_users(%{}, scope: scope) do
      {:ok, users} ->
        each(users, fn user ->
          case User.detach_for_organization_cleanup(user, %{}, scope: scope) do
            {:ok, _user} -> :ok
            {:error, error} -> {:error, error}
          end
        end)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc "Remove only the actual deleted account's OAuth dependents, even without an organization."
  @spec remove_account_oauth_dependents(Scope.t()) :: :ok | {:error, term()}
  def remove_account_oauth_dependents(scope) do
    args = %{user_id: scope.actor.user_id}

    with :ok <-
           destroy_records(
             OauthAuthorizationCode.read(args, scope: scope),
             &OauthAuthorizationCode.destroy/2,
             scope
           ),
         :ok <-
           destroy_records(OauthConsent.read(args, scope: scope), &OauthConsent.destroy/2, scope) do
      destroy_records(
        OauthRefreshToken.read(args, scope: scope),
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

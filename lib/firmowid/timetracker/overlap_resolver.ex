defmodule Firmowid.Timetracker.OverlapResolver do
  @moduledoc """
  Executes the overlap resolution plan computed by `TrimPlan`.

  Applies all trim/delete/split actions and creates the new session
  inside a single database transaction. Returns `{:ok, new_session}`
  on success or `{:error, reason}` on failure (transaction rolled back).
  """

  alias Firmowid.Scope
  alias Firmowid.Timetracker.Session

  @type trim_action ::
          {:trim_end, map(), DateTime.t()}
          | {:trim_start, map(), DateTime.t()}
          | {:delete, map()}
          | {:split, map(), DateTime.t(), map()}

  @doc """
  Atomically executes the trim plan and creates the new session.

  ## Parameters

    * `trim_actions` — list of actions from `TrimPlan.compute/3`
    * `new_session_attrs` — attributes for the new session to create
    * `scope` — `%Firmowid.Scope{}` struct (actor + tenant)

  ## Returns

    * `{:ok, new_session}` — all operations succeeded
    * `{:error, reason}` — transaction rolled back, reason is the first failure
  """
  @spec execute([trim_action()], map(), Scope.t()) ::
          {:ok, map()} | {:error, term()}
  def execute(trim_actions, new_session_attrs, scope) do
    # Ash doesn't provide a built-in primitive for atomically executing
    # heterogeneous actions (mixed updates + deletes + creates). Each individual
    # Ash call below runs inside this shared transaction via savepoints.
    Ash.DataLayer.transaction(
      Session,
      fn ->
        Enum.each(trim_actions, &execute_action!(&1, scope))
        create_session!(new_session_attrs, scope)
      end
    )
  end

  defp execute_action!({:trim_end, session, new_end}, scope) do
    ok_or_rollback!(Session.update(session, %{end_datetime: new_end}, scope: scope))
  end

  defp execute_action!({:trim_start, session, new_start}, scope) do
    ok_or_rollback!(Session.update(session, %{start_datetime: new_start}, scope: scope))
  end

  defp execute_action!({:delete, session}, scope) do
    ok_or_rollback!(Session.destroy(session, scope: scope))
  end

  defp execute_action!({:split, session, new_end, remainder_attrs}, scope) do
    ok_or_rollback!(Session.update(session, %{end_datetime: new_end}, scope: scope))
    ok_or_rollback!(Session.create(remainder_attrs, scope: scope))
  end

  @doc """
  Creates a session using the appropriate action based on the attributes.

  Uses `:create` when explicit times are provided (historical entry),
  or `:start` when no times are given (start a running session).
  """
  @spec create_session(map(), Scope.t()) :: {:ok, map()} | {:error, term()}
  def create_session(attrs, scope) do
    if attrs[:end_datetime] || attrs[:start_datetime] do
      Session.create(attrs, scope: scope)
    else
      Session.start(Map.take(attrs, [:title, :project_id, :is_remote]), scope: scope)
    end
  end

  defp create_session!(attrs, scope) do
    case create_session(attrs, scope) do
      {:ok, session} -> session
      {:error, error} -> Ash.DataLayer.rollback(Session, error)
    end
  end

  defp ok_or_rollback!(:ok), do: :ok
  defp ok_or_rollback!({:ok, _}), do: :ok
  defp ok_or_rollback!({:error, error}), do: Ash.DataLayer.rollback(Session, error)
end

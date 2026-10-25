defmodule Firmowid.Ash.AssistantTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures

  alias Firmowid.Ash.Assistant
  alias Firmowid.Ash.Assistant.Conversation
  alias Firmowid.Ash.Assistant.Conversation.Worker.Respond
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Scope

  @moduletag capture_log: true

  setup do
    owner = admin_fixture()
    %{owner: owner, scope: Scope.new!(owner, owner.member.organization_id)}
  end

  test "confirmation approves only unanswered calls in the persisted current plan", %{
    scope: scope
  } do
    Oban.Testing.with_testing_mode(:manual, fn ->
      conversation = pending_conversation(scope)
      [call] = Assistant.pending_calls(conversation)

      assert {:ok, approved} =
               Assistant.respond_to_plan(
                 conversation,
                 %{decision: :approve, expected_version: conversation.version},
                 scope: scope
               )

      assert approved.status == :running
      assert approved.version > conversation.version
      assert approved.approvals == %{call["id"] => "approve"}

      assert [%{args: args}] = all_enqueued(worker: Respond)
      assert args["action_arguments"] == %{"run_id" => approved.run_id}
      assert args["primary_key"] == %{"id" => conversation.id}
      assert args["tenant"] == scope.tenant

      assert {:error, _} =
               Assistant.respond_to_plan(
                 approved,
                 %{decision: :approve, expected_version: approved.version},
                 scope: scope
               )

      assert length(all_enqueued(worker: Respond)) == 1
    end)
  end

  test "stale consent cannot approve or deny a newer plan, even using the old record", %{
    scope: scope
  } do
    Oban.Testing.with_testing_mode(:manual, fn ->
      rendered = pending_conversation(scope)
      [call] = Assistant.pending_calls(rendered)
      replacement = Map.put(call, "id", "replacement-call")

      current =
        Ash.Seed.update!(rendered, %{
          version: rendered.version + 1,
          transcript: [
            %{"role" => "user", "text" => "Zaproponuj inne dopasowanie."},
            %{
              "role" => "assistant",
              "parts" => [%{"type" => "step"}, Map.put(replacement, "type", "tool_call")]
            }
          ]
        })

      for decision <- [:approve, :deny], snapshot <- [rendered, current] do
        assert {:error, _} =
                 Assistant.respond_to_plan(
                   snapshot,
                   %{decision: decision, expected_version: rendered.version},
                   scope: scope
                 )
      end

      persisted = Assistant.get_conversation!(current.id, scope: scope)
      assert persisted.version == current.version
      assert persisted.transcript == current.transcript
      assert persisted.approvals == %{}
      assert [] == all_enqueued(worker: Respond)

      assert {:ok, denied} =
               Assistant.respond_to_plan(
                 persisted,
                 %{decision: :deny, expected_version: persisted.version},
                 scope: scope
               )

      assert denied.approvals == %{"replacement-call" => "deny"}
      assert denied.status == :running
      assert length(all_enqueued(worker: Respond)) == 1
    end)
  end

  test "sending rejects busy conversations and an obsolete rendered version", %{
    scope: scope
  } do
    Oban.Testing.with_testing_mode(:manual, fn ->
      conversation = Assistant.get_or_create_conversation!(scope: scope)

      assert {:ok, running} =
               Assistant.send_message(
                 conversation,
                 %{text: "Znajdź przelew.", expected_version: conversation.version},
                 scope: scope
               )

      assert running.status == :running

      for snapshot <- [conversation, running] do
        assert {:error, _} =
                 Assistant.send_message(
                   snapshot,
                   %{text: "Druga wiadomość.", expected_version: snapshot.version},
                   scope: scope
                 )
      end

      assert length(all_enqueued(worker: Respond)) == 1

      assert Assistant.get_conversation!(running.id, scope: scope).transcript ==
               running.transcript
    end)
  end

  test "owners and independent tenants cannot read, send or consent to another conversation", %{
    scope: scope
  } do
    Oban.Testing.with_testing_mode(:manual, fn ->
      conversation = pending_conversation(scope)
      colleague = admin_fixture(%{organization_id: scope.tenant})
      outsider = admin_fixture()

      for actor <- [colleague, outsider] do
        other_scope = Scope.new!(actor, actor.member.organization_id)
        own = Assistant.get_or_create_conversation!(scope: other_scope)
        refute own.id == conversation.id
        assert own.user_id == actor.id
        assert own.organization_id == other_scope.tenant

        assert {:error, _} = Assistant.get_conversation(conversation.id, scope: other_scope)

        assert {:error, _} =
                 Assistant.send_message(
                   conversation,
                   %{text: "Cudza wiadomość.", expected_version: conversation.version},
                   scope: other_scope
                 )

        assert {:error, _} =
                 Assistant.respond_to_plan(
                   conversation,
                   %{decision: :approve, expected_version: conversation.version},
                   scope: other_scope
                 )
      end

      assert {:error, _} =
               Conversation.save_progress(conversation, %{status: :idle}, scope: scope)

      assert [] == all_enqueued(worker: Respond)

      same = Assistant.get_or_create_conversation!(scope: scope)
      assert same.id == conversation.id
      assert same.transcript == conversation.transcript
      assert same.version == conversation.version

      assert {:error, _} =
               Assistant.send_message(
                 same,
                 %{text: "Nie pomijaj planu.", expected_version: same.version},
                 scope: scope
               )
    end)
  end

  test "an interrupted approved run preserves financial links and cannot execute again or replace a newer run",
       %{
         owner: owner,
         scope: scope
       } do
    Oban.Testing.with_testing_mode(:manual, fn ->
      account = bank_account_fixture!(owner)

      transaction =
        Ash.Seed.seed!(Transaction, %{
          bank_account_id: account.id,
          organization_id: scope.tenant,
          amount: Money.new!(:PLN, -100),
          booking_date: ~D[2026-01-10],
          value_date: ~D[2026-01-10]
        })

      invoice =
        Ash.Seed.seed!(CostInvoice, %{
          organization_id: scope.tenant,
          seller: "Test Vendor",
          amount: Money.new!(:PLN, -100),
          issue_date: ~D[2026-01-01],
          sale_date: ~D[2026-01-01],
          due_date: ~D[2026-01-20]
        })

      Invoicing.connect_cost_invoice_transactions!(invoice, [transaction.id], scope: scope)

      arguments = Jason.encode!(%{id: invoice.id, input: %{transaction_ids: [transaction.id]}})

      completed = [
        %{"type" => "step"},
        %{
          "type" => "tool_call",
          "id" => "connected",
          "name" => "connect_cost_invoice_transactions",
          "arguments" => arguments
        },
        %{"type" => "tool_result", "id" => "connected", "content" => "Connected."}
      ]

      pending = %{
        "type" => "tool_call",
        "id" => "disconnect-pending",
        "name" => "disconnect_cost_invoice_transactions",
        "arguments" => arguments
      }

      conversation = pending_conversation(scope, completed ++ [%{"type" => "step"}, pending])

      approved =
        Assistant.respond_to_plan!(
          conversation,
          %{decision: :approve, expected_version: conversation.version},
          scope: scope
        )

      assert [%{args: args}] = all_enqueued(worker: Respond)
      assert :ok = perform_job(Respond, args, attempt: 2)

      interrupted = Assistant.get_conversation!(approved.id, scope: scope)
      assert interrupted.status == :failed
      assert interrupted.error == "interrupted"
      assert interrupted.approvals == %{}
      assert Assistant.pending_calls(interrupted) == []
      parts = List.last(interrupted.transcript)["parts"]
      assert Enum.take(parts, length(completed)) == completed
      assert List.last(parts)["id"] == "disconnect-pending"
      assert Jason.decode!(List.last(parts)["content"])["error"] =~ "Outcome unknown"

      assert :ok = perform_job(Respond, args)
      assert Assistant.get_conversation!(approved.id, scope: scope).version == interrupted.version

      fresh =
        Assistant.send_message!(
          interrupted,
          %{
            text: "Sprawdź aktualny stan i przygotuj nowy plan.",
            expected_version: interrupted.version
          },
          scope: scope
        )

      refute fresh.run_id == approved.run_id
      assert :ok = perform_job(Respond, args)
      persisted = Assistant.get_conversation!(fresh.id, scope: scope)
      assert persisted.status == :running
      assert persisted.version == fresh.version

      assert [%{id: id}] =
               Finances.get_transaction!(transaction.id, scope: scope, load: [:cost_invoices]).cost_invoices

      assert id == invoice.id
    end)
  end

  defp pending_conversation(scope, parts \\ nil) do
    parts =
      parts ||
        [
          %{"type" => "step"},
          %{
            "type" => "tool_call",
            "id" => "already-read",
            "name" => "list_transactions",
            "arguments" => "{}"
          },
          %{"type" => "tool_result", "id" => "already-read", "content" => "[]"},
          %{"type" => "step"},
          %{
            "type" => "tool_call",
            "id" => "change-1",
            "name" => "restore_transaction_for_matching",
            "arguments" => "{}"
          }
        ]

    Ash.Seed.seed!(Conversation, %{
      user_id: scope.actor.id,
      organization_id: scope.tenant,
      status: :awaiting_approval,
      transcript: [
        %{"role" => "user", "text" => "Przygotuj plan dopasowania."},
        %{"role" => "assistant", "parts" => parts}
      ]
    })
  end
end

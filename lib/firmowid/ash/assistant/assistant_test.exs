defmodule Firmowid.Ash.AssistantTest do
  @moduledoc false
  use Firmowid.DataCase

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures

  alias Ash.Error.Changes.StaleRecord
  alias AshStateMachine.Errors.NoMatchingTransition
  alias Firmowid.Ash.Assistant
  alias Firmowid.Ash.Assistant.Conversation
  alias Firmowid.Ash.Assistant.Conversation.Worker.Respond
  alias Firmowid.Ash.Assistant.Message
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Invoicing.SalesInvoice
  alias Firmowid.Ash.Scope
  alias Firmowid.Ash.Timetracker.Project

  @moduletag capture_log: true

  setup do
    owner = admin_fixture()
    %{owner: owner, scope: Scope.new!(owner, owner.member.organization_id)}
  end

  test "starting a conversation persists its first turn without touching running or pending conversations",
       %{
         scope: scope
       } do
    Oban.Testing.with_testing_mode(:manual, fn ->
      pending = pending_conversation(scope)
      running = Assistant.start_conversation!(%{text: "Pierwsze pytanie."}, scope: scope)
      fresh = Assistant.start_conversation!(%{text: "Pytanie o inną fakturę."}, scope: scope)

      assert fresh.id != running.id
      assert fresh.id != pending.id
      assert fresh.run_id != running.run_id
      assert fresh.status == :running
      assert fresh.version == 1
      assert fresh.user_id == scope.actor.id
      assert fresh.organization_id == scope.tenant
      assert fresh.approvals == %{}

      assert [message] = conversation_messages(fresh, scope)
      assert message.role == :user
      assert message.parts == [%{"type" => "text", "text" => "Pytanie o inną fakturę."}]
      assert message.organization_id == scope.tenant

      for previous <- [pending, running] do
        persisted = Assistant.get_conversation!(previous.id, scope: scope)
        assert conversation_messages(persisted, scope) == conversation_messages(previous, scope)
        assert persisted.status == previous.status
        assert persisted.version == previous.version
        assert persisted.run_id == previous.run_id
        assert persisted.approvals == previous.approvals
        assert persisted.updated_at == previous.updated_at
      end

      assert length(all_enqueued(worker: Respond)) == 2

      assert_enqueued(
        worker: Respond,
        args: %{
          primary_key: %{id: fresh.id},
          metadata: %{run_id: fresh.run_id},
          tenant: scope.tenant
        }
      )

      approved =
        Assistant.respond_to_plan!(
          pending,
          %{decision: :approve, expected_version: pending.version},
          scope: scope
        )

      assert approved.approvals == %{"change-1" => "approve"}
      assert Assistant.get_conversation!(fresh.id, scope: scope).approvals == %{}
      assert length(all_enqueued(worker: Respond)) == 3

      completed = Conversation.complete!(fresh, %{}, worker_opts(scope))
      assert completed.status == :idle
      assert completed.version == fresh.version + 1
      assert completed.run_id == fresh.run_id
      assert completed.approvals == %{}

      assert {:error, %{errors: errors}} =
               Conversation.append_response(
                 fresh,
                 %{role: :assistant, parts: [%{"type" => "text", "text" => "Nieaktualne."}]},
                 worker_opts(scope)
               )

      assert Enum.any?(errors, &match?(%StaleRecord{}, &1))
    end)
  end

  test "subject context stays idle until the first user message enqueues its response", %{
    owner: owner,
    scope: scope
  } do
    Oban.Testing.with_testing_mode(:manual, fn ->
      conversations =
        Enum.map(conversation_subjects(owner, scope), fn {type, subject, title} ->
          conversation =
            Assistant.start_subject_conversation!(
              %{subject_type: type, subject_id: subject.id},
              scope: scope
            )

          assert conversation.status == :idle
          assert conversation.version == 1
          assert conversation.run_id == nil
          assert conversation.user_id == scope.actor.id
          assert conversation.organization_id == scope.tenant
          assert conversation.approvals == %{}

          assert conversation.subject == %{
                   "type" => Atom.to_string(type),
                   "id" => subject.id,
                   "title" => title
                 }

          assert conversation_messages(conversation, scope) == []

          persisted = Assistant.get_conversation!(conversation.id, scope: scope, load: [:title])
          assert persisted.title == title
          assert persisted.subject == conversation.subject
          persisted
        end)

      assert [] == all_enqueued(worker: Respond)

      for conversation <- conversations do
        running =
          Assistant.send_message!(
            conversation,
            %{
              text: "Sprawdź płatność z poprzedniego miesiąca.",
              expected_version: conversation.version
            },
            scope: scope
          )

        assert running.status == :running
        assert running.version > conversation.version
        assert running.run_id

        assert [message] = conversation_messages(running, scope)
        assert message.role == :user

        assert message.parts == [
                 %{"type" => "text", "text" => "Sprawdź płatność z poprzedniego miesiąca."}
               ]

        assert_enqueued(
          worker: Respond,
          args: %{
            primary_key: %{id: conversation.id},
            metadata: %{run_id: running.run_id},
            tenant: scope.tenant
          }
        )
      end

      assert length(all_enqueued(worker: Respond)) == length(conversations)
    end)
  end

  test "subject reads preserve tenant and resource authorization and conversations remain owner-only",
       %{
         owner: owner,
         scope: scope
       } do
    Oban.Testing.with_testing_mode(:manual, fn ->
      outsider = admin_fixture()
      employee = user_fixture(%{organization_id: scope.tenant})
      colleague = admin_fixture(%{organization_id: scope.tenant})
      colleague_scope = Scope.new!(colleague, scope.tenant)

      for {type, subject, _title} <- conversation_subjects(owner, scope) do
        input = %{subject_type: type, subject_id: subject.id}

        for actor <- [outsider, employee] do
          other_scope = Scope.new!(actor, actor.member.organization_id)
          assert {:error, _} = Assistant.start_subject_conversation(input, scope: other_scope)

          assert %{results: []} =
                   Assistant.list_conversations!(scope: other_scope, page: [limit: 20])
        end

        conversation = Assistant.start_subject_conversation!(input, scope: scope)
        independent = Assistant.start_subject_conversation!(input, scope: colleague_scope)
        refute independent.id == conversation.id
        assert independent.user_id == colleague.id

        assert {:error, _} = Assistant.get_conversation(conversation.id, scope: colleague_scope)

        assert {:error, _} =
                 Assistant.send_message(
                   conversation,
                   %{text: "Odczytaj cudzy kontekst.", expected_version: conversation.version},
                   scope: colleague_scope
                 )

        persisted = Assistant.get_conversation!(conversation.id, scope: scope)
        assert persisted.status == :idle
        assert conversation_messages(persisted, scope) == []
        assert persisted.version == conversation.version
        assert persisted.run_id == nil
      end

      assert [] == all_enqueued(worker: Respond)
    end)
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
      assert args["metadata"] == %{"run_id" => approved.run_id}
      assert args["primary_key"] == %{"id" => conversation.id}
      assert args["tenant"] == scope.tenant

      assert {:error, %{errors: errors}} =
               Assistant.respond_to_plan(
                 approved,
                 %{decision: :approve, expected_version: approved.version},
                 scope: scope
               )

      assert Enum.any?(errors, &match?(%NoMatchingTransition{}, &1))
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

      append_message!(
        rendered,
        :user,
        [%{"type" => "text", "text" => "Zaproponuj inne dopasowanie."}],
        scope
      )

      append_message!(
        rendered,
        :tool,
        [%{"type" => "tool_result", "id" => call["id"], "content" => "Plan zastąpiony."}],
        scope
      )

      append_message!(
        rendered,
        :assistant,
        [%{"type" => "step"}, Map.put(replacement, "type", "tool_call")],
        scope
      )

      current = Ash.Seed.update!(rendered, %{version: rendered.version + 1})

      for decision <- [:approve, :deny], snapshot <- [rendered, current] do
        assert {:error, %{errors: errors}} =
                 Assistant.respond_to_plan(
                   snapshot,
                   %{decision: decision, expected_version: rendered.version},
                   scope: scope
                 )

        if snapshot == rendered do
          assert Enum.any?(errors, &match?(%StaleRecord{}, &1))
        else
          assert Enum.any?(errors, fn error ->
                   match?(%{field: :expected_version, message: "stale_conversation"}, error)
                 end)
        end
      end

      persisted = Assistant.get_conversation!(current.id, scope: scope)
      assert persisted.version == current.version
      assert conversation_messages(persisted, scope) == conversation_messages(current, scope)
      assert persisted.approvals == %{}
      assert [] == all_enqueued(worker: Respond)

      assert [new_call] =
               Assistant.pending_calls(%{
                 current
                 | messages: conversation_messages(current, scope)
               })

      assert new_call["id"] == "replacement-call"

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
      started = Assistant.start_conversation!(%{text: "Pierwsze pytanie."}, scope: scope)
      conversation = Ash.Seed.update!(started, %{status: :idle, version: started.version + 1})

      assert {:error, %{errors: errors}} =
               Assistant.send_message(
                 conversation,
                 %{text: "Wiadomość ze starego widoku.", expected_version: started.version},
                 scope: scope
               )

      assert Enum.any?(errors, fn error ->
               match?(%{field: :expected_version, message: "stale_conversation"}, error)
             end)

      assert {:ok, running} =
               Assistant.send_message(
                 conversation,
                 %{text: "Znajdź przelew.", expected_version: conversation.version},
                 scope: scope
               )

      assert running.status == :running

      for snapshot <- [started, conversation, running] do
        assert {:error, _} =
                 Assistant.send_message(
                   snapshot,
                   %{text: "Druga wiadomość.", expected_version: snapshot.version},
                   scope: scope
                 )
      end

      assert length(all_enqueued(worker: Respond)) == 2

      assert conversation_messages(running, scope) ==
               conversation_messages(
                 Assistant.get_conversation!(running.id, scope: scope),
                 scope
               )
    end)
  end

  test "owners and independent tenants cannot list, read, send or consent to another conversation",
       %{
         scope: scope
       } do
    Oban.Testing.with_testing_mode(:manual, fn ->
      conversation = pending_conversation(scope)
      colleague = admin_fixture(%{organization_id: scope.tenant})
      outsider = admin_fixture()

      foreign_tenant =
        Ash.Seed.seed!(Conversation, %{
          user_id: scope.actor.id,
          organization_id: outsider.member.organization_id
        })

      assert {:error, _} = Assistant.get_conversation(foreign_tenant.id, scope: scope)

      assert %{results: [%{id: id}]} =
               Assistant.list_conversations!(scope: scope, page: [limit: 20])

      assert id == conversation.id

      for actor <- [colleague, outsider] do
        other_scope = Scope.new!(actor, actor.member.organization_id)
        own = Assistant.start_conversation!(%{text: "Moje pytanie."}, scope: other_scope)
        refute own.id == conversation.id
        assert own.user_id == actor.id
        assert own.organization_id == other_scope.tenant

        assert %{results: [listed]} =
                 Assistant.list_conversations!(
                   scope: other_scope,
                   query: [select: [:id, :status, :inserted_at, :updated_at]],
                   load: [:title],
                   page: [limit: 20]
                 )

        assert listed.id == own.id
        assert listed.title == "Moje pytanie."
        refute Ash.Resource.selected?(listed, :messages)

        assert {:error, _} = Assistant.get_conversation(conversation.id, scope: other_scope)

        assert {:ok, []} =
                 Assistant.list_messages(%{conversation_id: conversation.id},
                   scope: other_scope,
                   page: false
                 )

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

        for {action, input} <- [
              append_response: %{
                role: :assistant,
                parts: [%{"type" => "text", "text" => "Odpowiedź."}]
              },
              await_approval: %{},
              complete: %{},
              fail: %{reason: "response_failed"}
            ] do
          assert {:error, %Ash.Error.Forbidden{}} =
                   apply(Conversation, action, [own, input, [scope: other_scope]])
        end
      end

      assert {:error, _} = Conversation.read_for_job(conversation.id, scope: scope)

      assert length(all_enqueued(worker: Respond)) == 2

      same = Assistant.get_conversation!(conversation.id, scope: scope)
      assert same.id == conversation.id
      assert conversation_messages(same, scope) == conversation_messages(conversation, scope)
      assert conversation_messages(same, scope) != []
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

      conversation =
        pending_conversation(
          scope,
          completed ++
            [%{"type" => "unsupported_interrupted_part"}, %{"type" => "step"}, pending]
        )

      approved =
        Assistant.respond_to_plan!(
          conversation,
          %{decision: :approve, expected_version: conversation.version},
          scope: scope
        )

      assert [%{args: args, id: job_id}] = all_enqueued(worker: Respond)

      # An unsupported earlier message fails before any provider/tool call, so
      # the native on_error action can close the approved call as UNKNOWN.
      assert %{discard: 1, cancelled: 0, success: 0, failure: 0, snoozed: 0} =
               Oban.drain_queue(queue: :assistant)

      assert %{state: "discarded", attempt: 1, max_attempts: 1} =
               Repo.get!(Oban.Job, job_id, prefix: "oban")

      interrupted = Assistant.get_conversation!(approved.id, scope: scope, load: [:messages])
      assert interrupted.status == :failed
      assert interrupted.error == "response_failed"
      assert interrupted.approvals == %{}
      interrupted_messages = conversation_messages(interrupted, scope)
      assert Assistant.pending_calls(%{interrupted | messages: interrupted_messages}) == []

      unknown =
        Enum.find(interrupted_messages, fn
          %{role: :tool, parts: [%{"id" => "disconnect-pending"} | _]} -> true
          _message -> false
        end)

      assert unknown

      assert Enum.any?(interrupted_messages, fn message ->
               Enum.any?(message.parts, &(&1["id"] == "disconnect-pending"))
             end)

      assert Enum.any?(unknown.parts, fn part ->
               part["id"] == "disconnect-pending" and
                 Jason.decode!(part["content"])["error"] =~ "Outcome unknown"
             end)

      assert {:error, %{errors: errors}} =
               Conversation.fail(interrupted, %{reason: "response_failed"}, worker_opts(scope))

      assert Enum.any?(errors, &match?(%NoMatchingTransition{}, &1))

      assert {:cancel, :trigger_no_longer_applies} = perform_job(Respond, args)
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
      assert {:cancel, :trigger_no_longer_applies} = perform_job(Respond, args)
      persisted = Assistant.get_conversation!(fresh.id, scope: scope)
      assert persisted.status == :running
      assert persisted.version == fresh.version

      assert [%{id: id}] =
               Finances.get_transaction!(transaction.id, scope: scope, load: [:cost_invoices]).cost_invoices

      assert id == invoice.id
    end)
  end

  defp conversation_subjects(owner, scope) do
    account = bank_account_fixture!(owner)

    transaction =
      Ash.Seed.seed!(Transaction, %{
        bank_account_id: account.id,
        organization_id: scope.tenant,
        amount: Money.new!(:PLN, -100),
        booking_date: ~D[2026-01-10],
        value_date: ~D[2026-01-10],
        remittance_information_unstructured: "Płatność za usługi"
      })

    sales_invoice =
      Ash.Seed.seed!(SalesInvoice, %{
        organization_id: scope.tenant,
        invoice_number: "FV/1/2026"
      })

    cost_invoice =
      Ash.Seed.seed!(CostInvoice, %{
        organization_id: scope.tenant,
        amount: Money.new!(:PLN, -100),
        invoice_identifier: "K/1/2026"
      })

    project =
      Ash.Seed.seed!(Project, %{
        organization_id: scope.tenant,
        name: "Projekt testowy"
      })

    [
      {:transaction, transaction, "Płatność za usługi"},
      {:sales_invoice, sales_invoice, "FV/1/2026"},
      {:cost_invoice, cost_invoice, "K/1/2026"},
      {:employee, owner, owner.member.name},
      {:project, project, "Projekt testowy"}
    ]
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

    conversation =
      Ash.Seed.seed!(Conversation, %{
        user_id: scope.actor.id,
        organization_id: scope.tenant,
        status: :running,
        run_id: Ash.UUID.generate()
      })

    append_message!(
      conversation,
      :user,
      [%{"type" => "text", "text" => "Przygotuj plan dopasowania."}],
      scope
    )

    seed_assistant_parts(conversation, parts, scope)

    conversation = Conversation.await_approval!(conversation, %{}, worker_opts(scope))
    Assistant.get_conversation!(conversation.id, scope: scope, load: [:messages])
  end

  defp seed_assistant_parts(conversation, parts, scope) do
    {specs, assistant_parts} =
      Enum.reduce(parts, {[], []}, fn
        %{"type" => "tool_result"} = part, {specs, assistant_parts} ->
          specs = flush_assistant_parts(specs, assistant_parts)
          {specs ++ [%{role: :tool, parts: [part]}], []}

        part, {specs, assistant_parts} ->
          {specs, assistant_parts ++ [part]}
      end)

    specs
    |> flush_assistant_parts(assistant_parts)
    |> Enum.each(fn %{role: role, parts: message_parts} ->
      append_message!(conversation, role, message_parts, scope)
    end)
  end

  defp flush_assistant_parts(specs, []), do: specs
  defp flush_assistant_parts(specs, parts), do: specs ++ [%{role: :assistant, parts: parts}]

  defp append_message!(conversation, role, parts, scope) do
    Ash.Seed.seed!(Message, %{
      conversation_id: conversation.id,
      organization_id: scope.tenant,
      role: role,
      parts: parts
    })
  end

  defp conversation_messages(conversation, scope) do
    messages =
      Assistant.list_messages!(%{conversation_id: conversation.id}, scope: scope, page: false)

    assert Enum.map(messages, & &1.id) == Enum.sort(Enum.map(messages, & &1.id))
    messages
  end

  defp worker_opts(scope) do
    [
      actor: %{assistant_worker?: true},
      tenant: scope.tenant,
      context: %{private: %{ash_oban?: true}}
    ]
  end
end

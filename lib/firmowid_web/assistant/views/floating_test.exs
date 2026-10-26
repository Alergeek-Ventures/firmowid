defmodule FirmowidWeb.Assistant.Views.FloatingTest do
  @moduledoc false
  use FirmowidWeb.ConnCase
  use Oban.Testing, repo: Firmowid.Repo, prefix: "oban"

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Ash.Assistant
  alias Firmowid.Ash.Assistant.Conversation
  alias Firmowid.Ash.Assistant.Conversation.Worker.Respond
  alias Firmowid.Ash.Assistant.Message
  alias Firmowid.Ash.Finances
  alias Firmowid.Ash.Finances.Transaction
  alias Firmowid.Ash.Invoicing
  alias Firmowid.Ash.Invoicing.CostInvoice
  alias Firmowid.Ash.Scope

  @moduletag capture_log: true

  test "a queued confirmation of the rendered old plan cannot approve a newer plan or unlink its payment",
       %{
         conn: conn
       } do
    Oban.Testing.with_testing_mode(:manual, fn ->
      owner = admin_fixture()
      scope = Scope.new!(owner, owner.member.organization_id)
      account = bank_account_fixture!(owner)

      transaction =
        Ash.Seed.seed!(Transaction, %{
          organization_id: scope.tenant,
          bank_account_id: account.id,
          amount: Money.new!(:PLN, -100),
          booking_date: ~D[2026-01-10],
          value_date: ~D[2026-01-10],
          creditor_name: "Plan Vendor",
          remittance_information_unstructured: "PLAN-INVOICE"
        })

      invoice =
        Ash.Seed.seed!(CostInvoice, %{
          organization_id: scope.tenant,
          seller: "Plan Vendor",
          seller_display_name: "Plan Vendor",
          invoice_identifier: "PLAN-INVOICE",
          amount: Money.new!(:PLN, -100),
          issue_date: ~D[2026-01-01],
          sale_date: ~D[2026-01-01],
          due_date: ~D[2026-01-20]
        })

      Invoicing.connect_cost_invoice_transactions!(invoice, [transaction.id], scope: scope)

      arguments = Jason.encode!(%{id: invoice.id, input: %{transaction_ids: [transaction.id]}})

      original_call = %{
        "type" => "tool_call",
        "id" => "old-connect",
        "name" => "connect_cost_invoice_transactions",
        "arguments" => arguments
      }

      conversation =
        seed_conversation(scope, owner, :awaiting_approval, [
          {:user, [%{"type" => "text", "text" => "Sprawdź dopasowanie płatności."}]},
          {:assistant, [%{"type" => "step"}, original_call]}
        ])

      {:ok, dashboard, _html} = conn |> log_in_user(owner) |> live(~p"/fakturowanie")
      assistant = find_live_child(dashboard, "floating-assistant-#{scope.tenant}")
      assistant |> element("#assistant-launcher") |> render_click()

      button =
        "#assistant-plan-#{conversation.version} button[phx-click='approve']:not([disabled])"

      assert has_element?(assistant, button)

      assert has_element?(
               assistant,
               "#assistant-plan-#{conversation.version} a[href='/kosztowe/#{invoice.id}']",
               "PLAN-INVOICE"
             )

      refute has_element?(assistant, "#assistant-form [role='alert']")

      [rendered_version] =
        assistant
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query(button)
        |> LazyHTML.attribute("phx-value-version")

      replacement_call = %{
        original_call
        | "id" => "new-disconnect",
          "name" => "disconnect_cost_invoice_transactions"
      }

      running = Ash.Seed.update!(conversation, %{status: :running})

      current =
        running
        |> Conversation.append_response!(
          %{role: :assistant, parts: [%{"type" => "step"}, replacement_call]},
          worker_opts(scope)
        )
        |> Conversation.await_approval!(%{}, worker_opts(scope))

      assert has_element?(
               assistant,
               "#assistant-plan-#{current.version} button[phx-click='approve']:not([disabled])"
             )

      refute has_element?(assistant, "#assistant-plan-#{rendered_version}")

      # Reproduce an already queued browser click: keep the version actually
      # rendered earlier, even though the real resource notifier delivered the new plan.
      render_click(assistant, "approve", %{
        "version" => rendered_version,
        "conversation-id" => conversation.id
      })

      assert has_element?(assistant, "#assistant-form [role='alert']")
      assert has_element?(assistant, "#assistant-plan-#{current.version}")
      refute has_element?(assistant, "#assistant-working")
      assert [] == all_enqueued(worker: Respond)

      persisted = Assistant.get_conversation!(conversation.id, scope: scope)
      assert persisted.status == :awaiting_approval
      assert persisted.version == current.version
      assert persisted.approvals == %{}

      other =
        seed_conversation(
          scope,
          owner,
          :awaiting_approval,
          [
            {:user, [%{"type" => "text", "text" => "Osobna rozmowa o płatności."}]},
            {:assistant, [%{"type" => "step"}, replacement_call]}
          ],
          current.version
        )

      assistant |> element("#assistant-history-toggle") |> render_click()

      assert has_element?(
               assistant,
               "#assistant-history-#{current.id}",
               "Sprawdź dopasowanie płatności."
             )

      assistant |> element("#assistant-history-#{other.id}") |> render_click()
      assert has_element?(assistant, "#firmowid-assistant[data-conversation-id='#{other.id}']")

      # Equal revisions in different conversations do not make consent transferable.
      for decision <- ["approve", "deny"] do
        render_click(assistant, decision, %{
          "version" => to_string(current.version),
          "conversation-id" => current.id
        })
      end

      assert [] == all_enqueued(worker: Respond)
      assert Assistant.get_conversation!(other.id, scope: scope).status == :awaiting_approval
      assert Assistant.get_conversation!(other.id, scope: scope).approvals == %{}

      # The browser hook supplies the current page even after sticky LiveView navigation.
      render_click(assistant, "new_conversation", %{"path" => "/fakturowanie"})
      assert has_element?(assistant, "#firmowid-assistant[data-conversation-id='new']")
      refute has_element?(assistant, "#assistant-plan-#{current.version}")

      render_submit(assistant, "send", %{
        "message" => "Queued message",
        "conversation_id" => other.id
      })

      assert [] == all_enqueued(worker: Respond)
      assert has_element?(assistant, "#assistant-form [role='alert']")

      render_click(assistant, "new_conversation", %{"path" => "/kosztowe/#{invoice.id}"})

      assert has_element?(
               assistant,
               "#assistant-panel a[href='/kosztowe/#{invoice.id}']",
               "PLAN-INVOICE"
             )

      refute has_element?(assistant, "#firmowid-assistant[data-conversation-id='new']")
      refute has_element?(assistant, "#assistant-working")
      assert [] == all_enqueued(worker: Respond)

      assistant |> element("#assistant-history-toggle") |> render_click()
      assistant |> element("#assistant-history-#{current.id}") |> render_click()
      assert has_element?(assistant, "#assistant-plan-#{current.version}")
      assert Assistant.get_conversation!(current.id, scope: scope).status == :awaiting_approval

      assert [%{id: invoice_id}] =
               Finances.get_transaction!(transaction.id, scope: scope, load: [:cost_invoices]).cost_invoices

      assert invoice_id == invoice.id
    end)
  end

  test "a malformed pending plan stays rejectable and cannot be approved",
       %{conn: conn} do
    Oban.Testing.with_testing_mode(:manual, fn ->
      owner = admin_fixture()
      scope = Scope.new!(owner, owner.member.organization_id)

      # AshAI may ask for approval before validating tool names and arguments.
      malformed_calls = [
        %{
          "type" => "tool_call",
          "id" => "malformed-json",
          "name" => "restore_transaction_for_matching",
          "arguments" => "{"
        },
        %{
          "type" => "tool_call",
          "id" => "malformed-ids",
          "name" => "connect_sales_invoice_transactions",
          "arguments" =>
            Jason.encode!(%{
              id: Ash.UUID.generate(),
              input: %{transaction_ids: "invalid"}
            })
        },
        %{
          "type" => "tool_call",
          "id" => "malformed-name",
          "name" => "invented_operation",
          "arguments" => "{}"
        }
      ]

      conversation =
        seed_conversation(scope, owner, :awaiting_approval, [
          {:user, [%{"type" => "text", "text" => "Przygotuj zmianę."}]},
          {:assistant, [%{"type" => "step"} | malformed_calls]}
        ])

      {:ok, dashboard, _html} = conn |> log_in_user(owner) |> live(~p"/fakturowanie")
      assistant = find_live_child(dashboard, "floating-assistant-#{scope.tenant}")
      assistant |> element("#assistant-launcher") |> render_click()

      plan = "#assistant-plan-#{conversation.version}"

      assert has_element?(assistant, plan)
      assert has_element?(assistant, "#{plan} button[phx-click='deny']:not([disabled])")
      refute has_element?(assistant, "#{plan} button[phx-click='approve']:not([disabled])")
      assert has_element?(assistant, "#{plan} p", "Odrzuć ten plan")
      assert has_element?(assistant, "#{plan} h4", "Nieznana operacja")

      assert {:ok, denied} =
               Assistant.respond_to_plan(
                 conversation,
                 %{decision: :deny, expected_version: conversation.version},
                 scope: scope
               )

      assert denied.approvals == %{
               "malformed-json" => "deny",
               "malformed-ids" => "deny",
               "malformed-name" => "deny"
             }

      assert denied.status == :running
      assert [%{args: args}] = all_enqueued(worker: Respond)
      assert args["metadata"] == %{"run_id" => denied.run_id}
    end)
  end

  defp seed_conversation(scope, owner, status, messages, version \\ 1) do
    [{:user, [%{"type" => "text", "text" => title} | _]} | _] = messages

    conversation =
      Ash.Seed.seed!(Conversation, %{
        organization_id: scope.tenant,
        user_id: owner.id,
        status: status,
        title: title,
        version: version
      })

    Enum.each(messages, fn {role, parts} ->
      Ash.Seed.seed!(Message, %{
        conversation_id: conversation.id,
        organization_id: scope.tenant,
        role: role,
        parts: parts
      })
    end)

    conversation
  end

  defp worker_opts(scope) do
    [
      actor: %{assistant_worker?: true},
      tenant: scope.tenant,
      context: %{private: %{ash_oban?: true}}
    ]
  end
end

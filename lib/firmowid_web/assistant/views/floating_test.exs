defmodule FirmowidWeb.Assistant.Views.FloatingTest do
  @moduledoc false
  use FirmowidWeb.ConnCase
  use Oban.Testing, repo: Firmowid.Repo, prefix: "oban"

  import Firmowid.AccountsFixtures
  import Firmowid.FinancesFixtures
  import Phoenix.LiveViewTest

  alias Firmowid.Assistant
  alias Firmowid.Assistant.Conversation
  alias Firmowid.Assistant.Conversation.Worker.Respond
  alias Firmowid.Assistant.Message
  alias Firmowid.Finances
  alias Firmowid.Finances.Transaction
  alias Firmowid.Invoicing
  alias Firmowid.Invoicing.CostInvoice
  alias Firmowid.Invoicing.SalesInvoice
  alias Firmowid.Scope
  alias Firmowid.Timetracker.Project

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

  test "a draft update card shows the buyer's tax ID and address it changes", %{conn: conn} do
    owner = admin_fixture()
    scope = Scope.new!(owner, owner.member.organization_id)

    draft = seed_draft(scope)

    arguments =
      Jason.encode!(%{
        id: draft.id,
        input: %{buyer_id: "1234563218", buyer_address: "ul. Inna 2, Kraków"}
      })

    conversation =
      seed_conversation(scope, owner, :awaiting_approval, [
        {:user, [%{"type" => "text", "text" => "Zmień nabywcę."}]},
        {:assistant,
         [
           %{
             "type" => "tool_call",
             "id" => "revise",
             "name" => "update_sales_invoice_draft",
             "arguments" => arguments
           }
         ]}
      ])

    {:ok, dashboard, _html} = conn |> log_in_user(owner) |> live(~p"/fakturowanie")
    assistant = find_live_child(dashboard, "floating-assistant-#{scope.tenant}")
    assistant |> element("#assistant-launcher") |> render_click()

    plan = "#assistant-plan-#{conversation.version}"

    assert has_element?(assistant, "#{plan} button[phx-click='approve']:not([disabled])")
    assert has_element?(assistant, "#{plan} del", "1111111111")
    assert has_element?(assistant, "#{plan} ins", "1234563218")
    assert has_element?(assistant, "#{plan} del", "ul. Przykładowa 1, Warszawa")
    assert has_element?(assistant, "#{plan} ins", "ul. Inna 2, Kraków")
  end

  test "an add sessions card shows which sessions are remote work", %{conn: conn} do
    owner = admin_fixture()
    scope = Scope.new!(owner, owner.member.organization_id)
    project = Ash.Seed.seed!(Project, %{organization_id: scope.tenant, name: "Projekt testowy"})

    arguments =
      Jason.encode!(%{
        input: %{
          sessions: [
            %{
              title: "Przegląd",
              project_id: project.id,
              start_datetime: "2026-11-04T08:00:00+01:00",
              end_datetime: "2026-11-04T10:00:00+01:00",
              is_remote: true
            }
          ]
        }
      })

    conversation =
      seed_conversation(scope, owner, :awaiting_approval, [
        {:user, [%{"type" => "text", "text" => "Dodaj rano."}]},
        {:assistant,
         [
           %{
             "type" => "tool_call",
             "id" => "add",
             "name" => "add_sessions",
             "arguments" => arguments
           }
         ]}
      ])

    {:ok, dashboard, _html} = conn |> log_in_user(owner) |> live(~p"/fakturowanie")
    assistant = find_live_child(dashboard, "floating-assistant-#{scope.tenant}")
    assistant |> element("#assistant-launcher") |> render_click()

    plan = "#assistant-plan-#{conversation.version}"

    assert has_element?(assistant, "#{plan} ins", "04.11.2026, 08:00–10:00 · Przegląd")
    assert has_element?(assistant, "#{plan} dt", "Praca zdalna")
  end

  test "a profile card shows a bank account number the member does not have yet", %{conn: conn} do
    owner = admin_fixture()

    plan =
      open_plan(conn, owner, "update_profile", %{
        input: %{name: "Jan Kowalski", bank_account_number: "PL61109010140000071219812874"}
      })

    assert has_element?(plan.view, "#{plan.id} button[phx-click='approve']:not([disabled])")
    assert has_element?(plan.view, "#{plan.id} ins", "Jan Kowalski")
    assert has_element?(plan.view, "#{plan.id} dt", "Numer konta bankowego")
    assert has_element?(plan.view, "#{plan.id} ins", "PL61109010140000071219812874")
  end

  test "an add sessions card reads remote work the way the action casts it", %{conn: conn} do
    owner = admin_fixture()

    project =
      Ash.Seed.seed!(Project, %{
        organization_id: owner.member.organization_id,
        name: "Projekt testowy"
      })

    plan =
      open_plan(conn, owner, "add_sessions", %{
        input: %{
          sessions: [
            %{
              title: "Przegląd",
              project_id: project.id,
              start_datetime: "2026-11-04T08:00:00+01:00",
              end_datetime: "2026-11-04T10:00:00+01:00",
              is_remote: "true"
            }
          ]
        }
      })

    assert has_element?(plan.view, "#{plan.id} button[phx-click='approve']:not([disabled])")
    assert has_element?(plan.view, "#{plan.id} dt", "Praca zdalna")
  end

  test "a draft card with a field on both levels of its input cannot be approved", %{conn: conn} do
    owner = admin_fixture()
    draft = seed_draft(Scope.new!(owner, owner.member.organization_id))

    # The action keeps the outer true because the inner null falls back to the field's default.
    plan =
      open_plan(conn, owner, "update_sales_invoice_draft", %{
        id: draft.id,
        input: %{
          buyer_address: "ul. Inna 2, Kraków",
          is_reverse_charge: true,
          input: %{is_reverse_charge: nil}
        }
      })

    assert has_element?(plan.view, "#{plan.id} button[phx-click='deny']:not([disabled])")
    refute has_element?(plan.view, "#{plan.id} button[phx-click='approve']:not([disabled])")
  end

  # Opens the assistant on a conversation that waits for approval of one tool call.
  defp open_plan(conn, owner, name, arguments) do
    scope = Scope.new!(owner, owner.member.organization_id)

    conversation =
      seed_conversation(scope, owner, :awaiting_approval, [
        {:user, [%{"type" => "text", "text" => "Zmień dane."}]},
        {:assistant,
         [
           %{
             "type" => "tool_call",
             "id" => "call",
             "name" => name,
             "arguments" => Jason.encode!(arguments)
           }
         ]}
      ])

    {:ok, dashboard, _html} = conn |> log_in_user(owner) |> live(~p"/fakturowanie")
    view = find_live_child(dashboard, "floating-assistant-#{scope.tenant}")
    view |> element("#assistant-launcher") |> render_click()

    %{view: view, id: "#assistant-plan-#{conversation.version}"}
  end

  # A draft of an organization whose seller data is complete enough to preview it.
  defp seed_draft(scope) do
    scope.tenant
    |> Firmowid.Core.get_organization!(scope: scope)
    |> Ash.Seed.update!(%{address: "ul. Sprzedawcy 3, Gdańsk"})

    Ash.Seed.seed!(SalesInvoice, %{
      organization_id: scope.tenant,
      issue_date: Date.utc_today(),
      sale_date: Date.utc_today(),
      due_date: Date.add(Date.utc_today(), 7),
      payment_method: :cash,
      currency: "PLN",
      buyer_type: :company,
      buyer_country: "PL",
      buyer_id: "1111111111",
      buyer_full_name: "Acme Sp. z o.o.",
      buyer_address: "ul. Przykładowa 1, Warszawa",
      sales_invoice_items: [
        %{
          organization_id: scope.tenant,
          index: 0,
          name: "Consulting",
          quantity: Decimal.new(1),
          unit: "szt",
          unit_price: Decimal.new(100),
          vat_rate: "23"
        }
      ]
    })
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

# Manual Matching AI Assistant

## Problem Statement

When automatic algorithms fail to match a bank **transaction** with a **sales / cost invoice**, people in **COO-like roles** (internal company staff managing finances and documentation, not external accountants) have to hunt through multiple screens and ad-hoc queries. A chat-based assistant (“Ask Firmowid”) should streamline this workflow by:

- Finding candidate transactions / invoices
- Highlighting similarities & differences (amount, counter-party, dates, references)
- Letting the user confirm, split, or dismiss matches interactively

## When is the assistant invoked?

Only for **non-trivial edge cases** where the automatic matcher fails and suggestion are irrelevant. Examples include:

- An invoice issued in one period but paid **months later**, so simple date-range matching misses it.
- A **single consolidated invoice** that covers **multiple transactions** (e.g. monthly T-Mobile phone bills paid together).
- Split payments, currency fluctuations, or partial refunds that confuse 1-to-1 matching logic.

## User Stories

1. _As a person managing finances/documentation_ I can ask the assistant for help when an invoice was paid late (e.g., issued in December, paid in March) and automatic matching fails.
2. _As a person managing finances/documentation_ I can indicate that an invoice groups multiple transactions (e.g., a consolidated phone bill with four card payments in a month).
3. _As a person managing finances/documentation_ I can explain that one transaction covers several invoices (e.g., a bulk transfer for multiple cost documents).
4. _As a person managing finances/documentation_ I can ask the assistant for help in cases with partial payments, refunds, or currency differences that prevent simple 1:1 matching.
5. _As a person managing finances/documentation_ I can describe an unusual situation and the assistant will suggest possible links and explain its reasoning.

## Implementation Plan (Streaming-First, LiveView, PubSub)

### Stage 0 (Already Done) PoC Foundations

- LlmComposer tool definitions, serializers, Ecto search, currency normaliser
- Agent-based `SessionConversation` persistence
- Non-streaming synchronous `Assistant.send_message/3`

### Stage 1 PubSub Backbone (≈10 LOC)

1. Add helper functions `topic/1`, `broadcast/2`, `subscribe/1`.
2. Modify `SessionConversation.append/2` to broadcast `{:new_message, msg}` after every insert.
3. Unit test – ensure message broadcast occurs.

### Stage 2 Streaming Kernel (≈40 LOC)

1. Introduce `do_completion_stream/3`:
   - calls `LlmComposer.run_completion/…` in `stream: true` mode
   - emits `{:stream_start, cid, first_chunk}`, `{:stream_chunk, cid, delta}`, `{:stream_end, cid, full}` via PubSub.
2. Wrap with `Assistant.send_message_async/3` (Task).
3. Keep action-handling loop intact.
4. Unit test – fake model, assert ordered PubSub events.

### Stage 3 LiveView Chat Component (≈150 LOC)

1. `ChatAssistantComponent`
   - `mount/3`: subscribe, preload history, initialise `:streamed` buffer.
   - `handle_event "send"`: call `Assistant.send_message_async/3`.
   - `handle_info` for the three stream events to update UI.
2. HEEx: render messages; use `<span phx-update="replace">` for streaming target.
3. Integration: invoke component on cost-invoice page, add “Zapytaj Firmowida” button.
4. LiveView test – assert progressive DOM growth while chunks arrive.

### Stage 4 User-level Polish (≈1 day)

- Style meta/function-result messages (grey/accordion).
- Auto-scroll to bottom on new chunks.
- Debounce typing indicator (optional).

### Stage 5 Operational Hardening

- Guard tenancy in `Assistant.subscribe/1` & page mounts.
- Rate-limit per organisation (Oban Cron or plug).
- Error telemetry: log streaming failures; fallback to full-response mode.

### Stage 6 Post-MVP Enhancements (optional)

- Token-level streaming to client via Server-Sent Events for ultra-low latency.
- Replace Agent with ETS + DynamicSupervisor for long-lived history.
- Add streaming support to other assistants (e.g. sales-invoice matcher).

#### Timeline Estimate

- Stage 1 – Stage 3: 1–1.5 days
- Stage 4: 0.5 day
- Stage 5: 0.5 day

### Current Status (2025-07-11)

- Assistant is fully working for:
  - Many transactions to one invoice scenario
  - Finding invoices not shown in recommendations
- Tools now read and write to the DB (not just pure functions).
- Scenarios for "many transactions to one invoice" and "exotic transaction" are implemented and sufficient for first deployment/evaluation.
- Using GPT-4.1 (cheaper, better, and fast enough for now).

### Lessons From Initial Testing

- **Conversation list management:**
  - Need to maintain three versions:
    - **Elixir version:** Structs for internal state
    - **LLM version:** Rendered to text prompts for the model
    - **UI version:** For highlighting agent actions (search, currency conversion, marking as done)
- **llm_composer:**
  - Useful, but requires workarounds (e.g., non-standard `:meta` message type)
  - Cannot use `auto_run_functions` as desired, since we want to save call context/results into function history
  - Uses Tesla/Hackney for HTTP, but would prefer to standardize on Req
- No new concrete lessons, but API for stored messages is sufficient for visualization; could be streamlined/simplified.

### Upcoming Work

- Refactor and streamline the assistant message API for easier visualization and maintenance.
- Expand scenarios as needed after first deployment/evaluation.

## 7. Data & Security

- **Row-level ACLs** exist already via tenant (`organization_id`). Reuse in queries.
- Keep OpenAI requests behind server – no keys in browser.

## 8. Open Questions

- (none for now)

# Outcome

Right now our autonomous matching handles up to 20% cases. Using recommendations with manual confirmation gets us to 85%. With assistant we should be able to cover 99.9% cases.

# Refactoring

The PoC proven our ideas but left the architecture coupled in a few places. The goal of this refactor is to separate _LLM transport_, _tool definitions_, _message persistence_, _assistant domain logic_ and _UI rendering_ so that future assistants (or even other LLM vendors) can be added with little friction.

### Objectives

- `LLMOpenAI` should **own all OpenAI-specific concerns** (request shape, streaming, tool → wire-format, etc.).
- `Tool` struct becomes the **single source of truth** for callable functions.
- `MessagesStorage` stores **pure Elixir structs only**, unaware of any particular LLM.
- Assistants only define
  - their _system prompt_,
  - their list of `Tool`s, and
  - a domain `exec_function/2` implementation.
- UI receives **rich payloads** (maps/structs) that it can turn into widgets; the LLM only gets plain text.

### Concrete Steps

1. **Enhance `Tool`**

   - Add fields `:description`, `:args_schema`, `:llm_render`, `:metadata`, `:handler`.
   - Provide `Tool.to_openai/1` helper.

2. **Update `LLMOpenAI`**

   - Accept `tools: [Tool.t()]`; internally call `Tool.to_openai/1`.
   - Keep request-body assembly (`model`, `function_call`, `stream`) inside the client.

3. **Refactor `MessagesStorage` & `Message`**

   - Add optional `payload` field to `Message` (
     ```elixir
     defstruct [:id, :role, :text, :payload, :timestamp]
     ```
     ).
   - Remove `get_as_open_ai_messages/1`.

4. **Introduce `AssistantEngine`** (new module)

   - Houses the generic function-call loop, streaming and token broadcast logic.
   - Takes: prompt, initial messages, tools, and an `exec_function/2` callback.

5. **Slim down `Matching.Assistant`**

   - Keep only prompt builder, `tools/0`, `exec_function/2`, and small helpers.
   - Delegate `send_message/…` to `AssistantEngine`.

6. **Update LiveView (`AssistantChatLive`)**

   - Pattern-match on `%Message{role: :tool_call | :tool_result, payload: p}`.

7. **Migration Path**
   1. Implement `Tool` changes and adjust existing tool definitions.
   2. Extend `Message` & `MessagesStorage` (run compiler).
   3. Extract `AssistantEngine` and port `Matching.Assistant`.
   4. Update `LLMOpenAI`.
   5. Adapt `AssistantChatLive` rendering clauses.
   6. Delete obsolete helpers (`serializers/0`, `to_openai_message/1`, etc.).
   7. Run tests & manual smoke-test.

This refactor clears the way for additional assistants (sales-invoice matcher, banking-FAQ bot, etc.) and for swapping the backend model (GPT-4o → Claude) with minimal surface change.

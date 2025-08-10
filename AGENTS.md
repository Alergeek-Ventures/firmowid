# Agent guidelines for Firmowid

This is a web application written using the Phoenix web framework.

## PROJECT RULES

**CRITICAL: These are the highest priority rules for this project. When implementing code, these rules take precedence over all other guidelines.**

1. **Organization-Based Access Control** - **Always** ensure `organization_id` is present in all database operations for proper multi-tenant data isolation and security.

   **Core principle:**
   - Every database query must be scoped to the current organization
   - The repository automatically adds `organization_id` filtering to queries (see `lib/firmowid/repo.ex`)
   - Never bypass organization scoping unless absolutely necessary

   **Valid exceptions for bypassing (using `oban_jobs: true` or similar flags):**
   - Oban job queries (jobs table lacks `organization_id` field - it's stored in JSON `args`/`meta`)
   - System-level operations that truly span all organizations
   - Migration or maintenance scripts with explicit justification

   **Implementation patterns:**

   ```elixir
   # ALWAYS: Include organization_id in queries
   Repo.all(User, organization_id: org_id)
   Repo.get(Post, post_id, organization_id: org_id)
   
   # ONLY when necessary: Bypass for Oban jobs
   Firmowid.Repo.put_org_id(org_id)
   jobs = Repo.all(Oban.Job, oban_jobs: true)
   
   # NEVER: Skip organization scoping without justification
   Repo.all(User)  # WRONG: Violates data isolation
   ```

   **Why this matters:**
   - Ensures data isolation between tenants
   - Prevents unauthorized data access
   - Maintains security boundaries in multi-tenant architecture
   - Critical for compliance and data privacy

2. **Ecto Query Composition** - **Always** construct database queries using Ecto schemas with composable query functions. Use the pipe operator (`|>`) to chain query operations for readability and maintainability.

   **Preferred approach:**

   ```elixir
   User
   |> where([u], u.active == true)
   |> where([u], u.age >= 18)
   |> order_by([u], desc: u.created_at)
   |> Repo.all()
   ```

   **Avoid:** Raw SQL queries or non-composable query construction.

3. **Code Simplification Through Reduced Branching** - **Always** strive to eliminate unnecessary conditional logic by analyzing the program flow deeply. Question every branching statement and seek ways to unify code paths.

   **Key principles:**
   - Eliminate defensive fallbacks like `x || []` when the empty case can be handled uniformly
   - Replace conditional operations on collections with unconditional transformations
   - When you see `if list != [] do process(list) end`, consider if `Enum.map/2` or similar operations would work for both empty and non-empty cases

   **Example transformations:**

   ```elixir
   # AVOID: Unnecessary branching
   items = get_items() || []
   if items != [] do
     Enum.map(items, &process/1)
   else
     []
   end
   
   # PREFER: Unified approach
   get_items()
   |> Enum.map(&process/1)  # look up the code and make sure nils are not passed from get_items
   ```

   **Analysis approach:** Before implementing any conditional logic, trace through the entire execution path to identify opportunities for simplification. Consider whether the branching is truly necessary or if a more elegant, unified solution exists.

4. **Transactional Data Integrity** - **Always** perform related database operations within transactions to maintain data consistency and prevent race conditions.

   **Key principles:**
   - Use `Ecto.Multi` for composing multiple database operations that must succeed or fail together
   - Never perform separate query-then-modify operations outside a transaction (introduces race conditions)
   - For operations involving external services (APIs, file systems), use Oban to schedule jobs within the transaction

   **Example patterns:**

   ```elixir
   # AVOID: Race condition between query and delete
   user = Repo.get!(User, id)
   if user.active do
     Repo.delete(user)
     Repo.insert(%Log{action: "deleted_user"})
   end
   
   # PREFER: Atomic transaction with Ecto.Multi
   Multi.new()
   |> Multi.run(:user, fn repo, _changes ->
     case repo.get(User, id) do
       %User{active: true} = user -> {:ok, user}
       _ -> {:error, :user_not_active}
     end
   end)
   |> Multi.delete(:delete_user, fn %{user: user} -> user end)
   |> Multi.insert(:log, %Log{action: "deleted_user"})
   |> Repo.transaction()
   
   # WITH EXTERNAL API: Use Oban for reliable async processing
   Multi.new()
   |> Multi.insert(:order, order_changeset)
   |> Oban.insert(:email_job, MyApp.EmailWorker.new(%{order_id: order.id}))
   |> Multi.run(:payment, fn _repo, %{order: order} ->
     # Schedule payment processing via Oban instead of direct API call
     {:ok, Oban.insert(MyApp.PaymentWorker.new(%{order_id: order.id}))}
   end)
   |> Repo.transaction()
   ```

   **External operations:** When transactions involve external services, use Oban to:
   - Schedule the external operation as a job within the transaction
   - Leverage Oban's built-in retry mechanisms and exponential backoff
   - Implement rate limiting and throttling for API calls
   - Ensure the external operation happens only if the transaction commits

5. **Structured Logging and Clean Test Output** - **Always** use Logger for application logging and be strategic about log capture in tests to maintain clean output while preserving debugging information.

   **Implementation principles:**
   - Require Logger at the module level for any module that needs logging
   - Use appropriate log levels (`:debug`, `:info`, `:warning`, `:error`)
   - In tests, **only capture expected logs** - let unexpected logs appear for debugging

   **Logging patterns:**

   ```elixir
   # In application code
   defmodule MyApp.Worker do
     require Logger
     
     def perform(args) do
       Logger.info("Starting job with args: #{inspect(args)}")
       
       case process(args) do
         {:ok, result} ->
           Logger.debug("Job completed successfully: #{inspect(result)}")
           {:ok, result}
           
         {:error, reason} ->
           Logger.error("Job failed: #{inspect(reason)}")
           {:error, reason}
       end
     end
   end
   ```

   **Test patterns:**

   ```elixir
   # AVOID: Blindly capturing all logs
   test "worker processes job" do
     import ExUnit.CaptureLog
     
     capture_log(fn ->
       # This hides ALL logs, including unexpected errors
       result = Worker.perform(%{id: 1})
       assert {:ok, _} = result
     end)
   end
   
   # PREFER: Capture only expected logs, let unexpected ones surface
   test "worker processes job successfully" do
     import ExUnit.CaptureLog
     
     # Capture and verify expected info logs
     log = capture_log([level: :info], fn ->
       assert {:ok, _} = Worker.perform(%{id: 1})
     end)
     
     assert log =~ "Starting job"
     # Unexpected errors/warnings will still appear in test output
   end
   
   # GOOD: Be specific about what you're capturing
   test "worker handles known error gracefully" do
     import ExUnit.CaptureLog
     
     # Only capture the expected error log
     log = capture_log([level: :error], fn ->
       assert {:error, :invalid} = Worker.perform(%{})
     end)
     
     assert log =~ "Job failed: :invalid"
   end
   ```

   **Testing strategy:**
   - Capture logs you **expect** and want to verify or suppress
   - Let **unexpected** logs (errors, warnings) appear in test output for debugging
   - Use log level filtering in `capture_log` to be selective
   - Consider what logs would help diagnose test failures

   **Log level guidelines:**
   - `:debug` - Detailed information for debugging (e.g., intermediate values, state changes)
   - `:info` - General informational messages (e.g., job started, request received)
   - `:warning` - Warning conditions that don't prevent operation (e.g., deprecated usage, retries)
   - `:error` - Error conditions and failures (e.g., exceptions, failed operations)

6. **Oban Testing with Organization-Scoped Repositories** - **Always** be aware of the interaction between Oban testing helpers and custom repository query preparation when working with multi-tenant applications.

   ### The Problem with assert_enqueued

   The `assert_enqueued` helper fails when used with custom repositories that have automatic query filtering. In this codebase, `lib/firmowid/repo.ex:39` automatically adds organization-based filtering to all queries:

   ```elixir
   # This tries to add: WHERE organization_id = ?
   {Ecto.Query.where(query, organization_id: ^organization_id), opts}
   ```

   But `Oban.Job` schema doesn't have an `organization_id` field - that data is stored in the JSON `args` or `meta` fields. So when `assert_enqueued` tries to query the jobs table, it fails with:

   ```
   field `organization_id` in `where` does not exist in schema Oban.Job
   ```

   ### Why :manual Mode Works

   Using `Oban.Testing.with_testing_mode(:manual)` prevents the job from executing immediately, allowing us to:
   1. Query the job directly using the original manual approach with `oban_jobs: true` option
   2. Bypass the repo's automatic filtering by using `Firmowid.Repo.put_org_id()` and `oban_jobs: true`
   3. Verify the job exists in the database before it gets processed and removed

   ### Testing Approach

   ```elixir
   # AVOID: Using assert_enqueued with org-scoped repos
   test "enqueues job" do
     MyWorker.new(%{org_id: org_id}) |> Oban.insert()
     assert_enqueued worker: MyWorker  # FAILS: organization_id field doesn't exist
   end
   
   # PREFER: Manual mode with direct query
   test "enqueues job" do
     Oban.Testing.with_testing_mode(:manual, fn ->
       MyWorker.new(%{org_id: org_id}) |> Oban.insert()
       
       # Query with oban_jobs flag to bypass org filtering
       Firmowid.Repo.put_org_id(org_id)
       jobs = Repo.all(Oban.Job, oban_jobs: true)
       assert length(jobs) == 1
       assert hd(jobs).worker == "MyWorker"
     end)
   end
   ```

7. **Strategic Testing - Avoid Overtesting** - **Always** focus testing efforts on high-value code and never write tests without explicit user request.

   **Core principle:**
   - Testing should provide value, not just coverage
   - Focus on business logic that transforms complex inputs into specific outputs
   - **Never** write tests proactively - always ask the user if tests are needed

   **High-value testing targets:**
   - **Business logic** - Complex calculations, data transformations, validation rules
   - **Critical paths** - Payment processing, authentication, authorization
   - **Edge cases** - Boundary conditions, error handling in complex flows
   - **Unit tests** - Functions with high complexity but small, predictable outputs

   **Low-value testing targets (avoid unless specifically requested):**
   - Simple getters/setters or pass-through functions
   - Direct Ecto schema CRUD operations without business logic
   - Phoenix controllers that only call context functions
   - View helpers that only format data

   **Testing patterns:**

   ```elixir
   # HIGH VALUE: Complex business logic
   test "calculates invoice tax with multiple rates and exemptions" do
     items = [
       %{price: 100, tax_rate: 0.23, exempt: false},
       %{price: 50, tax_rate: 0.08, exempt: true}
     ]
     assert Invoice.calculate_total_tax(items) == Decimal.new("23.00")
   end
   
   # LOW VALUE: Simple CRUD (avoid unless requested)
   test "creates a user" do
     assert {:ok, user} = Accounts.create_user(%{name: "John"})
     assert user.name == "John"  # Just testing Ecto, not your logic
   end
   ```

   **External API testing:**
   - Mock external services to test your handling logic
   - Use tools like `Req.Test.stub/2` for HTTP mocking
   - Focus on testing your error handling and data transformation, not the API itself

   ```elixir
   # GOOD: Test your handling of API responses
   test "handles payment provider errors gracefully" do
     Req.Test.stub(:payment_api, fn conn ->
       Plug.Conn.send_resp(conn, 503, "Service Unavailable")
     end)
     
     assert {:error, :payment_unavailable} = Payments.process_payment(order)
   end
   ```

   **Remember:** Always ask "What could break?" and "What would I want to know if it breaks?" before writing a test. If the answer is "Ecto/Phoenix internals," skip the test.

8. **External Boundaries as Behaviours (Mocks-as-Nouns)**

- Core principles:
  - Define behaviours (nouns) for all external boundaries (HTTP APIs, storage), and depend on those behaviours in app code
  - Provide concrete implementations per runtime (production vs test) via application env
  - In unit tests, use Mox to set expectations on behaviour contracts; reserve Req.Test or HTTP stubbing for optional integration tests only
  - This complements Rule 4 (Transactional integrity) and Rule 7 (Strategic testing) by isolating effects and testing only your logic

- Boundaries we will extract/standardize:
  - BankData.Client behaviour with implementations:
    - GoCardlessClient (production)
    - ClientMock via Mox (tests)
  - Blobs.Storage behaviour with implementations:
    - S3Storage (production)
    - LocalTestStorage (tests)

- Configuration (application env):
  - :bank_data_client -> production: GoCardlessClient; test: ClientMock (Mox)
  - :blobs_storage -> production: S3Storage; test: LocalTestStorage

- Implementation pattern:

```elixir
# behaviour (boundary)
defmodule Firmowid.BankData.Client do
  @callback requisition_status(binary()) :: {:ok, map()} | {:error, term()}
  @callback list_accounts(binary()) :: {:ok, [map()]} | {:error, term()}
  # ...other required callbacks
end

# production implementation
defmodule Firmowid.BankData.GoCardlessClient do
  @behaviour Firmowid.BankData.Client

  @impl true
  def requisition_status(id) do
    # perform HTTP via Req and transform to domain map
  end

  @impl true
  def list_accounts(requisition_id) do
    # ...
  end
end

# usage from app code (context/worker)
defmodule Firmowid.BankData.SomeService do
  @client Application.compile_env!(:firmowid, :bank_data_client)
  # or fetch at runtime if hot-swapping is required

  def check_status(req_id) do
    @client.requisition_status(req_id)
  end
end
```

- Testing with Mox:

```elixir
# test_helper.exs
Mox.defmock(Firmowid.BankData.ClientMock, for: Firmowid.BankData.Client)
Application.put_env(:firmowid, :bank_data_client, Firmowid.BankData.ClientMock)

# a test
test "processes status" do
  Firmowid.BankData.ClientMock
  |> Mox.expect(:requisition_status, fn _id -> {:ok, %{status: "LN"}} end)

  assert {:ok, _} = SomeService.check_status("req_123")
end
```

- Alignment with existing rules:
  - Rule 1 (Org-based access): behaviours should receive organization_id as explicit args where appropriate; never bypass scoping in callers
  - Rule 4 (Transactional integrity): schedule boundary work (e.g., API calls) via Oban when part of a transaction
  - Rule 5 (Structured logging): production implementations should log at appropriate levels; keep logs out of the behaviour interface
  - Rule 6 (Oban testing): when validating jobs enqueued by behaviour-driven code, use :manual mode and oban_jobs: true
  - Rule 7 (Strategic testing): unit tests mock behaviours; only add HTTP integration tests when they provide clear value

- Do / Don’t:
  - Do depend on behaviours from contexts/workers; don’t call HTTP libraries (Req/ExAws) directly in business code
  - Do configure implementations via env; don’t conditionally branch on Mix.env? within functions
  - Do use Mox for deterministic unit tests; don’t overuse Req.Test stubs in unit tests (keep them for integration)
  - Do keep behaviour contracts stable and small; don’t leak transport shapes into your domain (transform at the boundary)

## Build/Test Commands

- `mix test` - Run all tests
- `mix test test/path/to/specific_test.exs` - Run single test file
- `mix test --failed` - Run previously failed tests
- `mix format` - Format code (always run after changes)
- `mix setup` - Install deps, setup DB, build assets
- `mix ecto.reset` - Reset database

## Commit guidelines

- we abide by the Conventional Commits spec in this repository
- scopes are typically Elixir contexts that were modified by the commit
- lowercased text

## Elixir guidelines

- Elixir lists **do not support index based access via the access syntax**

  **Never do this (invalid)**:

      i = 0
      mylist = ["blue", "green"]
      mylist[i]

  Instead, **always** use `Enum.at`, pattern matching, or `List` for index based list access, ie:

      i = 0
      mylist = ["blue", "green"]
      Enum.at(mylist, i)

- Elixir supports `if/else` but **does NOT support `if/else if` or `if/elsif`. **Never use `else if` or `elseif` in Elixir**,**always\*\* use `cond` or `case` for multiple conditionals.

  **Never do this (invalid)**:

      <%= if condition do %>
        ...
      <% else if other_condition %>
        ...
      <% end %>

  Instead **always** do this:

      <%= cond do %>
        <% condition -> %>
          ...
        <% condition2 -> %>
          ...
        <% true -> %>
          ...
      <% end %>

- Elixir variables are immutable, but can be rebound, so for block expressions like `if`, `case`, `cond`, etc
  you _must_ bind the result of the expression to a variable if you want to use it and you CANNOT rebind the result inside the expression, ie:

      # INVALID: we are rebinding inside the `if` and the result never gets assigned
      if connected?(socket) do
        socket = assign(socket, :val, val)
      end

      # VALID: we rebind the result of the `if` to a new variable
      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`
- **Never** nest multiple modules in the same file as it can cause cyclic dependencies and compilation errors
- **Never** use map access syntax (`changeset[:field]`) on structs as they do not implement the Access behaviour by default. For regular structs, you **must** access the fields directly, such as `my_struct.field` or use higher level APIs that are available on the struct if they exist, `Ecto.Changeset.get_field/2` for changesets
- Elixir's standard library has everything necessary for date and time manipulation. Familiarize yourself with the common `Time`, `Date`, `DateTime`, and `Calendar` interfaces by accessing their documentation as necessary. **Never** install additional dependencies unless asked or for date/time parsing (which you can use the `date_time_parser` package)
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Predicate function names should not start with `is_` and should end in a question mark. Names like `is_thing` should be reserved for guards
- Elixir's builtin OTP primitives like `DynamicSupervisor` and `Registry`, require names in the child spec, such as `{DynamicSupervisor, name: Firmowid.MyDynamicSup}`, then you can use `DynamicSupervisor.start_child(Firmowid.MyDynamicSup, child_spec)`
- Use `Task.async_stream(collection, callback, options)` for concurrent enumeration with back-pressure. The majority of times you will want to pass `timeout: :infinity` as option

## Mix guidelines

- Read the docs and options before using tasks (by using `mix help task_name`)
- To debug test failures, run tests in a specific file with `mix test test/my_test.exs` or run all previously failed tests with `mix test --failed`
- `mix deps.clean --all` is **almost never needed**. **Avoid** using it unless you have good reason

## Phoenix guidelines

- Remember Phoenix router `scope` blocks include an optional alias which is prefixed for all routes within the scope. **Always** be mindful of this when creating routes within a scope to avoid duplicate module prefixes.

- You **never** need to create your own `alias` for route definitions! The `scope` provides the alias, ie:

      scope "/admin", AppWeb.Admin do
        pipe_through :browser

        live "/users", UserLive, :index
      end

  the UserLive route would point to the `AppWeb.Admin.UserLive` module

- `Phoenix.View` no longer is needed or included with Phoenix, don't use it

## Ecto Guidelines

- **Always** preload Ecto associations in queries when they'll be accessed in templates, ie a message that needs to reference the `message.user.email`
- Remember `import Ecto.Query` and other supporting modules when you write `seeds.exs`
- `Ecto.Schema` fields always use the `:string` type, even for `:text`, columns, ie: `field :name, :string`
- `Ecto.Changeset.validate_number/2` **DOES NOT SUPPORT the `:allow_nil` option**. By default, Ecto validations only run if a change for the given field exists and the change value is not nil, so such as option is never needed
- You **must** use `Ecto.Changeset.get_field(changeset, :field)` to access changeset fields
- Fields which are set programatically, such as `user_id`, must not be listed in `cast` calls or similar for security purposes. Instead they must be explicitly set when creating the struct

## Phoenix HTML guidelines

- Phoenix templates **always** use `~H` or .html.heex files (known as HEEx), **never** use `~E`
- **Always** use the imported `Phoenix.Component.form/1` and `Phoenix.Component.inputs_for/1` function to build forms. **Never** use `Phoenix.HTML.form_for` or `Phoenix.HTML.inputs_for` as they are outdated
- When building forms **always** use the already imported `Phoenix.Component.to_form/2` (`assign(socket, form: to_form(...))` and `<.form for={@form} id="msg-form">`), then access those forms in the template via `@form[:field]`
- **Always** add unique DOM IDs to key elements (like forms, buttons, etc) when writing templates, these IDs can later be used in tests (`<.form for={@form} id="product-form">`)
- For "app wide" template imports, you can import/alias into the `firmowid_web.ex`'s `html_helpers` block, so they will be available to all LiveViews, LiveComponent's, and all modules that do `use FirmowidWeb, :html` (replace "firmowid" by the actual app name)

- HEEx require special tag annotation if you want to insert literal curly's like `{` or `}`. If you want to show a textual code snippet on the page in a `<pre>` or `<code>` block you _must_ annotate the parent tag with `phx-no-curly-interpolation`:

      <code phx-no-curly-interpolation>
        let obj = {key: "val"}
      </code>

  Within `phx-no-curly-interpolation` annotated tags, you can use `{` and `}` without escaping them, and dynamic Elixir expressions can still be used with `<%= ... %>` syntax

- HEEx class attrs support lists, but you must **always** use list `[...]` syntax. You can use the class list syntax to conditionally add classes, **always do this for multiple class values**:

      <a class={[
        "px-2 text-white",
        @some_flag && "py-5",
        if(@other_condition, do: "border-red-500", else: "border-blue-100"),
        ...
      ]}>Text</a>

  and **always** wrap `if`'s inside `{...}` expressions with parens, like done above (`if(@other_condition, do: "...", else: "...")`)

  and **never** do this, since it's invalid (note the missing `[` and `]`):

      <a class={
        "px-2 text-white",
        @some_flag && "py-5"
      }> ...
      => Raises compile syntax error on invalid HEEx attr syntax

- **Never** use `<% Enum.each %>` or non-for comprehensions for generating template content, instead **always** use `<%= for item <- @collection do %>`
- HEEx HTML comments use `<%!-- comment --%>`. **Always** use the HEEx HTML comment syntax for template comments (`<%!-- comment --%>`)
- HEEx allows interpolation via `{...}` and `<%= ... %>`, but the `<%= %>` **only** works within tag bodies. **Always** use the `{...}` syntax for interpolation within tag attributes, and for interpolation of values within tag bodies. **Always** interpolate block constructs (if, cond, case, for) within tag bodies using `<%= ... %>`.

  **Always** do this:

      <div id={@id}>
        {@my_assign}
        <%= if @some_block_condition do %>
          {@another_assign}
        <% end %>
      </div>

  and **Never** do this – the program will terminate with a syntax error:

      <%!-- THIS IS INVALID NEVER EVER DO THIS --%>
      <div id="<%= @invalid_interpolation %>">
        {if @invalid_block_construct do}
        {end}
      </div>

## Phoenix LiveView guidelines

- **Never** use the deprecated `live_redirect` and `live_patch` functions, instead **always** use the `<.link navigate={href}>` and `<.link patch={href}>` in templates, and `push_navigate` and `push_patch` functions LiveViews
- **Avoid LiveComponent's** unless you have a strong, specific need for them
- LiveViews should be named like `AppWeb.WeatherLive`, with a `Live` suffix. When you go to add LiveView routes to the router, the default `:browser` scope is **already aliased** with the `AppWeb` module, so you can just do `live "/weather", WeatherLive`
- Remember anytime you use `phx-hook="MyHook"` and that js hook manages its own DOM, you **must** also set the `phx-update="ignore"` attribute
- **Never** write embedded `<script>` tags in HEEx. Instead always write your scripts and hooks in the `assets/js` directory and integrate them with the `assets/js/app.js` file

### LiveView streams

- **Always** use LiveView streams for collections for assigning regular lists to avoid memory ballooning and runtime termination with the following operations:

  - basic append of N items - `stream(socket, :messages, [new_msg])`
  - resetting stream with new items - `stream(socket, :messages, [new_msg], reset: true)` (e.g. for filtering items)
  - prepend to stream - `stream(socket, :messages, [new_msg], at: -1)`
  - deleting items - `stream_delete(socket, :messages, msg)`

- When using the `stream/3` interfaces in the LiveView, the LiveView template must 1) always set `phx-update="stream"` on the parent element, with a DOM id on the parent element like `id="messages"` and 2) consume the `@streams.stream_name` collection and use the id as the DOM id for each child. For a call like `stream(socket, :messages, [new_msg])` in the LiveView, the template would be:

      <div id="messages" phx-update="stream">
        <div :for={{id, msg} <- @streams.messages} id={id}>
          {msg.text}
        </div>
      </div>

- LiveView streams are _not_ enumerable, so you cannot use `Enum.filter/2` or `Enum.reject/2` on them. Instead, if you want to filter, prune, or refresh a list of items on the UI, you **must refetch the data and re-stream the entire stream collection, passing reset: true**:

      def handle_event("filter", %{"filter" => filter}, socket) do
        # re-fetch the messages based on the filter
        messages = list_messages(filter)

        {:noreply,
        socket
        |> assign(:messages_empty?, messages == [])
        # reset the stream with the new messages
        |> stream(:messages, messages, reset: true)}
      end

- LiveView streams _do not support counting or empty states_. If you need to display a count, you must track it using a separate assign. For empty states, you can use Tailwind classes:

      <div id="tasks" phx-update="stream">
        <div class="hidden only:block">No tasks yet</div>
        <div :for={{id, task} <- @stream.tasks} id={id}>
          {task.name}
        </div>
      </div>

  The above only works if the empty state is the only HTML block alongside the stream for-comprehension.

- **Never** use the deprecated `phx-update="append"` or `phx-update="prepend"` for collections

### LiveView tests

- `Phoenix.LiveViewTest` module and `LazyHTML` (included) for making your assertions
- Form tests are driven by `Phoenix.LiveViewTest`'s `render_submit/2` and `render_change/2` functions
- Come up with a step-by-step test plan that splits major test cases into small, isolated files. You may start with simpler tests that verify content exists, gradually add interaction tests
- **Always reference the key element IDs you added in the LiveView templates in your tests** for `Phoenix.LiveViewTest` functions like `element/2`, `has_element/2`, selectors, etc
- **Never** tests again raw HTML, **always** use `element/2`, `has_element/2`, and similar: `assert has_element?(view, "#my-form")`
- Instead of relying on testing text content, which can change, favor testing for the presence of key elements
- Focus on testing outcomes rather than implementation details
- Be aware that `Phoenix.Component` functions like `<.form>` might produce different HTML than expected. Test against the output HTML structure, not your mental model of what you expect it to be
- When facing test failures with element selectors, add debug statements to print the actual HTML, but use `LazyHTML` selectors to limit the output, ie:

      html = render(view)
      document = LazyHTML.from_fragment(html)
      matches = LazyHTML.filter(document, "your-complex-selector")
      IO.inspect(matches, label: "Matches")

### Form handling

#### Creating a form from params

If you want to create a form based on `handle_event` params:

    def handle_event("submitted", params, socket) do
      {:noreply, assign(socket, form: to_form(params))}
    end

When you pass a map to `to_form/1`, it assumes said map contains the form params, which are expected to have string keys.

You can also specify a name to nest the params:

    def handle_event("submitted", %{"user" => user_params}, socket) do
      {:noreply, assign(socket, form: to_form(user_params, as: :user))}
    end

#### Creating a form from changesets

When using changesets, the underlying data, form params, and errors are retrieved from it. The `:as` option is automatically computed too. E.g. if you have a user schema:

    defmodule Firmowid.Users.User do
      use Ecto.Schema
      ...
    end

And then you create a changeset that you pass to `to_form`:

    %Firmowid.Users.User{}
    |> Ecto.Changeset.change()
    |> to_form()

Once the form is submitted, the params will be available under `%{"user" => user_params}`.

In the template, the form form assign can be passed to the `<.form>` function component:

    <.form for={@form} id="todo-form" phx-change="validate" phx-submit="save">
      <.input field={@form[:field]} type="text" />
    </.form>

Always give the form an explicit, unique DOM ID, like `id="todo-form"`.

#### Avoiding form errors

**Always** use a form assigned via `to_form/2` in the LiveView, and the `<.input>` component in the template. In the template **always access forms this**:

    <%!-- ALWAYS do this (valid) --%>
    <.form for={@form} id="my-form">
      <.input field={@form[:field]} type="text" />
    </.form>

And **never** do this:

    <%!-- NEVER do this (invalid) --%>
    <.form for={@changeset} id="my-form">
      <.input field={@changeset[:field]} type="text" />
    </.form>

- You are FORBIDDEN from accessing the changeset in the template as it will cause errors
- **Never** use `<.form let={f} ...>` in the template, instead **always use `<.form for={@form} ...>`**, then drive all form references from the form assign as in `@form[:field]`. The UI should **always** be driven by a `to_form/2` assigned in the LiveView module that is derived from a changeset

## Project guidelines

- Use `mix format` alias when you are done with all changes and fix any pending issues
- Use the already included and available `:req` (`Req`) library for HTTP requests, **avoid** `:httpoison`, `:tesla`, and `:httpc`. Req is included by default and is the preferred HTTP client for Phoenix apps

### Phoenix v1.8 guidelines

- **Always** begin your LiveView templates with `<Layouts.app flash={@flash} ...>` which wraps all inner content
- The `FirmowidWeb.Layouts` module is aliased in the `firmowid_web.ex` file, so you can use it without needing to alias it again
- Anytime you run into errors with no `current_scope` assign:
  - You failed to follow the Authenticated Routes guidelines, or you failed to pass `current_scope` to `<Layouts.app>`
  - **Always** fix the `current_scope` error by moving your routes to the proper `live_session` and ensure you pass `current_scope` as needed
- Phoenix v1.8 moved the `<.flash_group>` component to the `Layouts` module. You are **forbidden** from calling `<.flash_group>` outside of the `layouts.ex` module
- Out of the box, `core_components.ex` imports an `<.icon name="hero-x-mark" class="w-5 h-5"/>` component for for hero icons. **Always** use the `<.icon>` component for icons, **never** use `Heroicons` modules or similar
- **Always** use the imported `<.input>` component for form inputs from `core_components.ex` when available. `<.input>` is imported and using it will will save steps and prevent errors
- If you override the default input classes (`<.input class="myclass px-2 py-1 rounded-lg">)`) class with your own values, no default classes are inherited, so your
  custom classes must fully style the input

### JS and CSS guidelines

- **Use Tailwind CSS classes and custom CSS rules** to create polished, responsive, and visually stunning interfaces.
- Tailwindcss v4 **no longer needs a tailwind.config.js** and uses a new import syntax in `app.css`:

      @import "tailwindcss" source(none);
      @source "../css";
      @source "../js";
      @source "../../lib/firmowid_web";

- **Always use and maintain this import syntax** in the app.css file for projects generated with `phx.new`
- **Never** use `@apply` when writing raw css
- **Always** manually write your own tailwind-based components instead of using daisyUI for a unique, world-class design
- Out of the box **only the app.js and app.css bundles are supported**
  - You cannot reference an external vendor'd script `src` or link `href` in the layouts
  - You must import the vendor deps into app.js and app.css to use them
  - **Never write inline <script>custom js</script> tags within templates**

### UI/UX & design guidelines

- **Produce world-class UI designs** with a focus on usability, aesthetics, and modern design principles
- Implement **subtle micro-interactions** (e.g., button hover effects, and smooth transitions)
- Ensure **clean typography, spacing, and layout balance** for a refined, premium look
- Focus on **delightful details** like hover effects, loading states, and smooth page transitions

## Authentication

- **Always** handle authentication flow at the router level with proper redirects
- **Always** be mindful of where to place routes. `phx.gen.auth` creates multiple router plugs and `live_session` scopes:
  - A `live_session :current_user` scope - For routes that need the current user but don't require authentication
  - A `live_session :require_authenticated_user` scope - For routes that require authentication
  - In both cases, a `@current_scope` is assigned to the Plug connection and LiveView socket
- **Always let the user know in which router scopes, `live_session`, and pipeline you are placing the route, AND SAY WHY**
- `phx.gen.auth` assigns the `current_scope` assign - it **does not assign the `current_user` assign**.
- To derive/access `current_user`, **always use the `current_scope.user` assign**, never use **`@current_user`** in templates or LiveViews
- **Never** duplicate `live_session` names. A `live_session :current_user` can only be defined **once** in the router, so all routes for the `live_session :current_user` must be grouped in a single block
- Anytime you hit `current_scope` errors or the logged in session isn't displaying the right content, **always double check the router and ensure you are using the correct `live_session` described below**

### Routes that require authentication

LiveViews that require login should **always be placed inside the **existing** `live_session :require_authenticated_user` block**:

    scope "/", AppWeb do
      pipe_through [:browser, :require_authenticated_user]

      live_session :require_authenticated_user,
        on_mount: [{AppWeb.UserAuth, :ensure_authenticated}] do
        # phx.gen.auth generated routes
        live "/users/settings", UserSettingsLive, :edit
        live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
        # our own routes that require logged in user
        live "/", MyLiveThatRequiresAuth, :index
      end
    end

### Routes that work with or without authentication

LiveViews that can work with or without authentication, **always use the **existing** `:current_user` scope**, ie:

    scope "/", FirmowidWeb do
      pipe_through [:browser]

      live_session :current_user,
        on_mount: [{FirmowidWeb.UserAuth, :mount_current_scope}] do
        # our own routes that work with or without authentication
        live "/", PublicLive
      end
    end

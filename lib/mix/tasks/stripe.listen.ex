defmodule Mix.Tasks.Stripe.Listen do
  @shortdoc "Forwards Stripe's test events to the running worktree app"
  @moduledoc """
  Forwards the events Firmowid listens to from the Stripe test account to this worktree's
  running app, until Ctrl-C.

      mix stripe.listen

  It runs the Stripe CLI (`stripe listen`) with the development key (`STRIPE_SECRET_KEY`), so no
  `stripe login` and no public URL are needed. The app checks the events with
  `STRIPE_WEBHOOK_SECRET`, which must be the CLI's signing secret; Stripe keeps one per key, and
  the task refuses to start when the two differ. Both come from Infisical dev `/app`.

  The test account is shared: every listener gets every event. Subscriptions of organizations
  this database does not know are ignored, but every paid invoice is recorded as a payment.
  """

  use Mix.Task
  use Phoenix.VerifiedRoutes, router: FirmowidWeb.Core.Router

  alias Firmowid.Billing.StripeEvents
  alias FirmowidWeb.Core.Endpoint

  @impl Mix.Task
  def run([]) do
    Mix.Task.run("app.config")

    stripe =
      System.find_executable("stripe") ||
        Mix.raise("The Stripe CLI is not on PATH. Enter the project's development environment.")

    key =
      Application.get_env(:stripity_stripe, :api_key) ||
        Mix.raise("STRIPE_SECRET_KEY is not set. It comes from Infisical dev /app.")

    if !String.contains?(key, "_test_") do
      Mix.raise("mix stripe.listen forwards test events only, and STRIPE_SECRET_KEY is not a test key.")
    end

    env = [{"STRIPE_API_KEY", key}]
    check_signing_secret!(stripe, env)

    port = Application.fetch_env!(:firmowid, Endpoint)[:http][:port]

    # A port's child gets no Ctrl-C and outlives Mix, so the supervisor stops it with Mix.
    {_output, status} =
      System.cmd(
        System.find_executable("bash"),
        [
          Application.app_dir(:firmowid, "priv/scripts/client_supervisor.bash"),
          List.to_string(:os.getpid()),
          stripe,
          "listen",
          "--forward-to",
          url(URI.new!("http://localhost:#{port}"), ~p"/webhooks/stripe"),
          "--events",
          Enum.join(StripeEvents.types(), ",")
        ],
        env: env,
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if status != 0, do: Mix.raise("stripe listen exited with status #{status}.")
  end

  def run(_args), do: Mix.raise("Usage: mix stripe.listen (no arguments)")

  defp check_signing_secret!(stripe, env) do
    {secret, 0} = System.cmd(stripe, ["listen", "--print-secret"], env: env)

    if String.trim(secret) != Application.get_env(:firmowid, :stripe)[:webhook_secret] do
      Mix.raise("""
      STRIPE_WEBHOOK_SECRET is not the signing secret of `stripe listen` for the development \
      Stripe key, so the app would reject every event. Store the output of \
      `stripe listen --print-secret` (run with that key as STRIPE_API_KEY) in Infisical dev /app \
      and restart the app.
      """)
    end
  end
end

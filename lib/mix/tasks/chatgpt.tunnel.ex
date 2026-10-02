defmodule Mix.Tasks.Chatgpt.Tunnel do
  @shortdoc "Runs the shared ChatGPT development tunnel in the foreground"
  @moduledoc """
  Runs the existing worktree's `/mcp-chatgpt` endpoint through Secure MCP Tunnel.

      mix chatgpt.tunnel

  Requires trusted `bash`, `infisical` and `tunnel-client` binaries on PATH and an existing
  Firmowid Infisical login/project selection. Reads only `.server.port` and the two
  shared transport credentials in dev `/dev/openai-tunnel`. Does not start the app.
  Agree on shared tunnel ownership first; only one operator may run it at a time.
  A fixed Bash supervisor forwards INT/TERM/HUP and monitors the Mix OS PID.
  On parent exit it terminates, waits for, and if needed kills only its own direct
  tunnel child. Confirm exit before handing over; no other processes are stopped.
  """

  use Mix.Task

  # Never copy application credentials, proxies, shell startup hooks or client
  # configuration. Use only inherited names, without inspecting/logging values.
  @system_env ~w(PATH HOME SSL_CERT_FILE SSL_CERT_DIR LANG LC_ALL LC_CTYPE)

  @impl Mix.Task
  def run([]) do
    # This is a Mix-only development launcher, never application runtime code.
    # credo:disable-for-next-line Credo.Check.Warning.MixEnv
    if Mix.env() != :dev, do: Mix.raise("mix chatgpt.tunnel is development-only (MIX_ENV=dev).")

    root = Mix.Project.project_file() |> Path.expand() |> Path.dirname()
    infisical = executable!("infisical")
    client = executable!("tunnel-client")
    bash = executable!("bash")
    supervisor = Path.join(root, "priv/scripts/chatgpt_tunnel_supervisor.bash")
    parent_pid = parent_pid!()
    port = read_port!(root)
    args = tunnel_args(port)
    env = child_env()

    check_help!(client, ["run", "--help"], required_flags(args), root, env)

    check_help!(
      infisical,
      ["secrets", "get", "--help"],
      ["--secret-overriding", "--silent", "--plain"],
      root,
      []
    )

    key = fetch_secret!(infisical, "CONTROL_PLANE_API_KEY", root)
    id = fetch_secret!(infisical, "CONTROL_PLANE_TUNNEL_ID", root)
    credentials = credential_env(key, id)

    Mix.shell().info("Forwarding http://localhost:#{port}/mcp-chatgpt; Ctrl-C to stop your client.")

    case command!(bash, [supervisor, parent_pid, client | args],
           cd: root,
           env: env |> Map.new() |> Map.merge(Map.new(credentials)) |> Map.to_list(),
           stderr_to_stdout: true,
           into: IO.stream(:stdio, :line)
         ) do
      {_, 0} ->
        :ok

      {_, status} ->
        Mix.raise("tunnel-client exited (status #{status}). Check safe JSON logs above.")
    end
  end

  def run(_args), do: Mix.raise("Usage: mix chatgpt.tunnel (no arguments or target overrides)")

  @doc "Validates the worktree port without including file contents in errors."
  @spec parse_port(String.t()) :: 1..65_535
  def parse_port(contents) do
    value = String.trim(contents)

    if Regex.match?(~r/\A[0-9]{1,5}\z/, value) do
      port = String.to_integer(value)
      if port in 1..65_535, do: port, else: invalid_port!()
    else
      invalid_port!()
    end
  end

  @doc "Builds fixed local-only tunnel arguments, never containing credentials."
  @spec tunnel_args(1..65_535) :: [String.t()]
  def tunnel_args(port) when is_integer(port) and port in 1..65_535 do
    [
      "run",
      "--mcp.server-url=http://localhost:#{port}/mcp-chatgpt",
      "--harpoon.allow-plaintext-http",
      "--control-plane.base-url=https://api.openai.com",
      "--control-plane.url-path=",
      "--control-plane.poll-channel=main",
      "--control-plane.poll-channel=harpoon",
      "--health.listen-addr=127.0.0.1:0",
      "--log.format=json",
      "--log.level=info",
      "--log.http-raw-unsafe=false",
      "--harpoon.capture-payloads=false",
      "--allow-remote-ui=false",
      "--open-web-ui=false",
      "--cloudflared.managed=false"
    ]
  end

  @doc "Unsets every inherited env name except explicit PATH, HOME, TLS and locale settings."
  @spec child_env() :: [{String.t(), nil}]
  def child_env do
    System.get_env()
    |> Map.keys()
    |> Enum.reject(&(&1 in @system_env))
    |> Enum.map(&{&1, nil})
  end

  @doc "Validates shared credentials and returns only their child environment bindings."
  @spec credential_env(String.t(), String.t()) :: [{String.t(), String.t()}]
  def credential_env(key, id) do
    key = String.trim(key)
    id = String.trim(id)

    if !(Regex.match?(~r/\Ask-[A-Za-z0-9_-]{16,}\z/, key) and
           key not in ["sk-xxxxxxxxxxxxxxxx", "sk-your_key_replace_me"]) do
      Mix.raise("Missing, placeholder or invalid CONTROL_PLANE_API_KEY in dev /dev/openai-tunnel.")
    end

    if !(Regex.match?(~r/\Atunnel_[0-9a-f]{32}\z/, id) and
           id != "tunnel_0123456789abcdef0123456789abcdef" and
           id != "tunnel_00000000000000000000000000000000") do
      Mix.raise("Missing, placeholder or invalid CONTROL_PLANE_TUNNEL_ID in dev /dev/openai-tunnel.")
    end

    [{"CONTROL_PLANE_API_KEY", key}, {"CONTROL_PLANE_TUNNEL_ID", id}]
  end

  # sobelow_skip ["Traversal.FileModule"]
  # Fixed filename derived from Mix's current project file, not web/user path input.
  # Reject symlinks to avoid reading a port file outside this worktree.
  defp read_port!(root) do
    path = Path.join(root, ".server.port")

    with {:ok, %{type: :regular}} <- File.lstat(path),
         {:ok, contents} <- File.read(path) do
      parse_port(contents)
    else
      _ ->
        Mix.raise(
          "Missing or unreadable regular .server.port in the Mix project worktree. Ask the developer to check the existing server."
        )
    end
  end

  @spec invalid_port!() :: no_return()
  defp invalid_port!, do: Mix.raise("Invalid .server.port: expected a decimal port in 1..65535.")

  defp parent_pid! do
    pid = List.to_string(:os.getpid())

    if Regex.match?(~r/\A[1-9][0-9]*\z/, pid),
      do: pid,
      else: Mix.raise("Could not determine the Mix OS process ID; refusing unsupervised launch.")
  end

  defp executable!(name) do
    System.find_executable(name) ||
      Mix.raise(
        "Required #{name} binary is absent from PATH. Enter the project's development environment or ask the developer to provision it; no automatic install."
      )
  end

  defp required_flags(args) do
    args |> Enum.drop(1) |> Enum.map(&(&1 |> String.split("=", parts: 2) |> hd())) |> Enum.uniq()
  end

  defp check_help!(binary, args, flags, root, env) do
    case command!(binary, args, cd: root, env: env, stderr_to_stdout: true) do
      {help, 0} ->
        if !Enum.all?(flags, &String.contains?(help, &1)) do
          Mix.raise(
            "Required CLI options unsupported. Ask the developer to check the installed #{Path.basename(binary)} version; no automatic upgrade."
          )
        end

      _ ->
        Mix.raise("Could not check #{Path.basename(binary)} CLI compatibility; output suppressed.")
    end
  end

  defp fetch_secret!(binary, name, root) do
    args = [
      "secrets",
      "get",
      name,
      "--domain",
      "https://infisical.alergeek.me",
      "--env",
      "dev",
      "--path",
      "/dev/openai-tunnel",
      "--plain",
      "--secret-overriding=false",
      "--silent"
    ]

    case command!(binary, args, cd: root, stderr_to_stdout: true) do
      {value, 0} ->
        String.trim(value)

      _ ->
        Mix.raise(
          "Could not retrieve #{name} from dev /dev/openai-tunnel. Check Firmowid Infisical login/project and permissions; output suppressed."
        )
    end
  end

  defp command!(binary, args, options) do
    System.cmd(binary, args, options)
  rescue
    _ ->
      Mix.raise("Could not execute #{Path.basename(binary)}; details suppressed to protect credentials.")
  end
end

Mix.install([{:req, "~> 0.7.4"}], lockfile: Path.expand("../mix.lock", __DIR__))

defmodule Firmowid.Translations.Accent do
  @moduledoc "Prepares and exports the Polish Accent translation catalog."

  @root Path.expand("..", __DIR__)
  @config Path.join(@root, "accent.json")
  @catalog Path.join(@root, "priv/gettext/default.pot")

  @request_timeout 30_000
  @cli_timeout "120"
  @usage "usage: accent.exs <prepare|export> --version FULL_SHA"
  @version_marker ~r/^# Accent version: [[:xdigit:]]{40}$/
  @bad_plural "\"Plural-Forms: nplrls=3; plural===1 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);\\n\""
  @good_plural "\"Plural-Forms: nplurals=3; plural=(n==1 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);\\n\""

  @create_version_query """
  mutation CreateVersion(
    $projectId: ID!
    $nameGitSHA: String!
    $tagSHA: String!
    $copyOnUpdateTranslation: Boolean!
  ) {
    createVersion(
      projectId: $projectId
      name: $nameGitSHA
      tag: $tagSHA
      copyOnUpdateTranslation: $copyOnUpdateTranslation
    ) {
      version { id tag }
      errors
    }
  }
  """

  @doc """
  Runs the standalone Accent operation.

  The operation is either `prepare` or `export`, and both require a full Git
  SHA in the form `--version FULL_SHA`.
  """
  @spec run([String.t()]) :: :ok
  def run(["prepare", "--version", version]), do: run_operation(:prepare, version)
  def run(["export", "--version", version]), do: run_operation(:export, version)
  def run(_args), do: raise(RuntimeError, message: @usage)

  defp run_operation(operation, version) do
    validate_version(version)
    context = context()

    case operation do
      :prepare ->
        prepare(context, version)

      :export ->
        :ok
    end

    with_temp_directory(fn temporary_directory ->
      export_catalog(version, temporary_directory)
      install_catalog(temporary_directory, version)
    end)

    :ok
  end

  defp validate_version(version) when is_binary(version) do
    if Regex.match?(~r/^[[:xdigit:]]{40}$/, version) do
      :ok
    else
      raise RuntimeError, "version must be a full 40-character Git SHA"
    end
  end

  defp context do
    %{"apiUrl" => api_url, "project" => project} =
      @config |> File.read!() |> JSON.decode!()

    %{
      project: System.get_env("ACCENT_PROJECT", project),
      client:
        Req.new(
          base_url: "ACCENT_API_URL" |> System.get_env(api_url) |> String.trim_trailing("/"),
          auth: {:bearer, System.fetch_env!("ACCENT_API_KEY")},
          receive_timeout: @request_timeout,
          connect_options: [timeout: 10_000],
          retry: false
        )
    }
  end

  defp prepare(context, version) do
    case request_status(context.client,
           method: :get,
           url: "/export",
           params: export_params(context, version)
         ) do
      {:ok, 200} ->
        :ok

      {:ok, 404} ->
        create_version(context, version)

      {:ok, status} ->
        raise RuntimeError, "Accent request failed (HTTP #{status})"

      {:error, :network_failure} ->
        raise RuntimeError, "Accent request failed (network or timeout)"
    end
  end

  defp export_params(context, version) do
    [
      project_id: context.project,
      language: "pl",
      document_format: "gettext",
      document_path: "gettext/landing-native",
      inline_render: true,
      order_by: "index",
      version: version
    ]
  end

  defp create_version(context, version) do
    body = %{
      "query" => @create_version_query,
      "variables" => %{
        "projectId" => context.project,
        "nameGitSHA" => "Git " <> version,
        "tagSHA" => version,
        "copyOnUpdateTranslation" => false
      }
    }

    case request_status(context.client, method: :post, url: "/graphql", json: body) do
      {:ok, 200} ->
        :ok

      {:ok, status} ->
        raise RuntimeError, "Accent version creation failed (HTTP #{status})"

      {:error, :network_failure} ->
        raise RuntimeError, "Accent version creation failed"
    end
  end

  defp request_status(client, options) do
    case Req.request(client, options) do
      {:ok, %Req.Response{status: status}} -> {:ok, status}
      {:error, _reason} -> {:error, :network_failure}
    end
  end

  defp with_temp_directory(callback) do
    temporary_directory =
      Path.join(
        @root,
        "tmp/accent." <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)
      )

    File.mkdir_p!(Path.dirname(temporary_directory))
    File.mkdir!(temporary_directory)

    try do
      File.chmod!(temporary_directory, 0o700)
      callback.(temporary_directory)
    after
      File.rm_rf!(temporary_directory)
    end
  end

  defp export_catalog(version, temporary_directory) do
    source = Path.join(temporary_directory, "gettext/landing-native/default.pot")
    File.mkdir_p!(Path.dirname(source))
    File.cp!(@catalog, source)

    accent_executable =
      System.find_executable("accent") ||
        raise(RuntimeError, "Accent CLI is required; enter the devenv environment")

    arguments = [
      @cli_timeout,
      accent_executable,
      "export",
      "--config",
      @config,
      "--version",
      version
    ]

    case System.cmd("timeout", arguments, cd: temporary_directory, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {_output, status} -> raise RuntimeError, "Accent CLI export failed (exit status #{status})"
    end
  end

  defp install_catalog(temporary_directory, version) do
    input = Path.join(temporary_directory, "exports/pl/default.po")
    text = File.read!(input)

    if text == "" do
      raise RuntimeError, "Accent export produced an empty PO file"
    end

    lines = text |> String.split("\n", trim: false) |> remove_old_version_marker()
    content = Enum.join(["# Accent version: #{version}" | fix_plural_header(lines)], "\n")
    output = Path.join(@root, "priv/gettext/pl/LC_MESSAGES/default.po")
    temporary_output = Path.join(temporary_directory, "catalog.po")

    File.mkdir_p!(Path.dirname(output))
    File.write!(temporary_output, content)
    File.rename!(temporary_output, output)
  end

  defp remove_old_version_marker(lines), do: Enum.reject(lines, &Regex.match?(@version_marker, &1))

  defp fix_plural_header(lines) do
    {fixed_lines, _state} = Enum.map_reduce(lines, :before, &fix_header_line/2)
    fixed_lines
  end

  defp fix_header_line("msgid \"\"" = line, :before), do: {line, :header}
  defp fix_header_line("msgstr \"\"" = line, :header), do: {line, :header_values}
  defp fix_header_line(@bad_plural, :header_values), do: {@good_plural, :header_values}

  defp fix_header_line(line, :header_values) do
    if String.starts_with?(line, ["\"", "#"]), do: {line, :header_values}, else: {line, :done}
  end

  defp fix_header_line(line, state), do: {line, state}
end

Firmowid.Translations.Accent.run(System.argv())

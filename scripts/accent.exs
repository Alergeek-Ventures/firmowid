Mix.install([{:req, "~> 0.7.4"}, {:expo, "~> 1.1"}],
  lockfile: Path.expand("../mix.lock", __DIR__)
)

Code.require_file("../lib/firmowid/translations.ex", __DIR__)

defmodule Firmowid.Translations.Accent do
  @moduledoc """
  Builds and installs the translated Gettext catalogs.

  `snapshot` exports the current Accent catalog, validates every translated locale
  against the source POT and installs it marked with a commit SHA. CI publishes the
  snapshot of each main commit as `<sha>.tar.gz` in the `translation-snapshots`
  GitHub release; `export` installs such a published snapshot, so deployment builds
  use exactly the catalog CI validated for their commit.
  """

  @root Path.expand("..", __DIR__)
  @config Path.join(@root, "accent.json")
  @catalog Path.join(@root, "priv/gettext/default.pot")

  @snapshot_url "https://github.com/Alergeek-Ventures/firmowid/releases/download/translation-snapshots"
  @request_timeout 30_000
  @usage "usage: accent.exs snapshot --version FULL_SHA | accent.exs export --version FULL_SHA [--fallback-version FULL_SHA]"
  @version_marker ~r/^# Accent version: [[:xdigit:]]{40}$/

  @doc """
  Runs the standalone operation.

  `snapshot` needs an Accent key and fails when a locale catalog is incomplete.
  `export` downloads the published snapshot of a full SHA, falling back to the
  explicit fallback SHA only when the requested one is not published.
  """
  @spec run([String.t()]) :: :ok
  def run(["snapshot", "--version", version]) do
    validate_version(version)
    api_key = api_key()

    with_temp_directory(fn temporary_directory ->
      export_catalog(temporary_directory, api_key)
      install_catalog(temporary_directory, version)
    end)
  end

  def run(["export", "--version", version]), do: run(["export", "--version", version, "--fallback-version", version])

  def run(["export", "--version", version, "--fallback-version", fallback]) do
    validate_version(version)
    validate_version(fallback)

    with_temp_directory(fn temporary_directory ->
      selected = download_snapshot(version, fallback, temporary_directory)
      install_snapshot(temporary_directory, selected)
    end)
  end

  def run(_args), do: raise(RuntimeError, message: @usage)

  defp validate_version(version) do
    if Regex.match?(~r/^[[:xdigit:]]{40}$/, version),
      do: :ok,
      else: raise(RuntimeError, "version must be a full 40-character Git SHA")
  end

  defp download_snapshot(version, fallback, temporary_directory) do
    case Req.get("#{@snapshot_url}/#{version}.tar.gz",
           receive_timeout: @request_timeout,
           connect_options: [timeout: 10_000],
           retry: false,
           decode_body: false
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        :ok =
          :erl_tar.extract({:binary, body}, [
            :compressed,
            {:cwd, String.to_charlist(temporary_directory)}
          ])

        version

      {:ok, %Req.Response{status: 404}} when version != fallback ->
        IO.puts("No published translation snapshot for #{version}; using #{fallback}")
        download_snapshot(fallback, fallback, temporary_directory)

      {:ok, %Req.Response{status: 404}} ->
        raise RuntimeError, "No published translation snapshot for #{version}"

      {:ok, %Req.Response{status: status}} ->
        raise RuntimeError, "Translation snapshot download failed (HTTP #{status})"

      {:error, reason} ->
        raise RuntimeError,
              "Translation snapshot download failed (transport: #{error_kind(reason)})"
    end
  end

  # A published snapshot was validated by CI for its commit; install it unchanged.
  defp install_snapshot(temporary_directory, version) do
    Enum.each(Firmowid.Translations.locales(), fn locale ->
      relative = "#{locale}/LC_MESSAGES/default.po"
      content = File.read!(Path.join(temporary_directory, relative))

      if List.first(String.split(content, "\n", parts: 2)) != "# Accent version: #{version}" do
        raise RuntimeError, "Published #{locale} snapshot is not marked with #{version}"
      end

      write_catalog(Path.join(@root, "priv/gettext/" <> relative), content, temporary_directory)
    end)
  end

  defp api_key do
    case System.get_env("ACCENT_API_KEY") do
      key when is_binary(key) and key != "" ->
        key

      _missing_or_empty ->
        if local_infisical_fallback?() do
          fetch_local_api_key()
        else
          raise RuntimeError,
                "ACCENT_API_KEY is required; local Infisical fallback is disabled outside local development"
        end
    end
  end

  defp local_infisical_fallback? do
    not truthy?(System.get_env("CI")) and System.get_env("MIX_ENV") != "prod" and
      not truthy?(System.get_env("AV_SKIP_INFISICAL"))
  end

  defp truthy?(value), do: value in ["1", "true"]

  defp fetch_local_api_key do
    infisical =
      System.find_executable("infisical") ||
        raise(RuntimeError,
          message:
            "ACCENT_API_KEY is missing and the Infisical CLI is unavailable; enter devenv and run `infisical login --domain=https://infisical.alergeek.me`"
        )

    arguments = [
      infisical,
      "secrets",
      "get",
      "ACCENT_API_KEY",
      "--domain",
      "https://infisical.alergeek.me",
      "--env=dev",
      "--path=/app",
      "--plain",
      "--silent"
    ]

    case System.cmd(
           "sh",
           ["-c", "exec timeout 20 \"$@\" </dev/null 2>/dev/null", "sh" | arguments],
           cd: @root
         ) do
      {output, 0} ->
        key = String.trim(output)

        if key == "" do
          raise RuntimeError,
                "Infisical returned an empty ACCENT_API_KEY; run `infisical login --domain=https://infisical.alergeek.me` and retry"
        end

        key

      {_output, 124} ->
        raise RuntimeError,
              "Infisical timed out fetching ACCENT_API_KEY; check connectivity, then run `infisical login --domain=https://infisical.alergeek.me` if needed"

      {_output, _status} ->
        raise RuntimeError,
              "Could not fetch ACCENT_API_KEY from Infisical; run `infisical login --domain=https://infisical.alergeek.me` and retry"
    end
  end

  defp error_kind(%Req.TransportError{reason: reason}), do: transport_kind(reason)
  defp error_kind(_error), do: "other"

  # Keep the transport allowlist aligned with Firmowid.ErrorKind without loading
  # its Ash/Ecto dependencies into this standalone script. Never stringify reasons.
  defp transport_kind(reason) when reason in [:timeout, :etimedout], do: "timeout"
  defp transport_kind(reason) when reason in [:nxdomain, :eai_again], do: "dns"
  defp transport_kind(reason) when reason in [:closed, :econnreset], do: "closed"
  defp transport_kind(:econnrefused), do: "refused"
  defp transport_kind(:protocol_not_negotiated), do: "tls"
  defp transport_kind({tag, _}) when tag in [:tls_alert, :bad_alpn_protocol, :bad_cert], do: "tls"
  defp transport_kind(_reason), do: "other"

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

  defp export_catalog(temporary_directory, api_key) do
    %{
      "apiUrl" => api_url,
      "project" => project,
      "files" => [%{"source" => source, "format" => format}]
    } =
      @config |> File.read!() |> JSON.decode!()

    Enum.each(Firmowid.Translations.locales(), fn locale ->
      result =
        Req.get(api_url <> "/export",
          auth: {:bearer, api_key},
          params: [
            document_path: Path.dirname(source),
            document_format: format,
            language: locale,
            project_id: project,
            order_by: "index"
          ],
          receive_timeout: @request_timeout,
          connect_options: [timeout: 10_000],
          retry: false,
          redirect: false,
          decode_body: false
        )

      case result do
        {:ok, %Req.Response{status: 200, body: body}} ->
          path = Path.join(temporary_directory, "exports/#{locale}/default.po")
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, body)

        {:ok, %Req.Response{status: status}} ->
          raise RuntimeError, "Accent export failed (HTTP #{status})"

        {:error, reason} ->
          raise RuntimeError, "Accent export failed (transport: #{error_kind(reason)})"
      end
    end)
  end

  defp install_catalog(temporary_directory, version) do
    Enum.each(Firmowid.Translations.locales(), &install_locale(temporary_directory, version, &1))
  end

  defp install_locale(temporary_directory, version, locale) do
    input = Path.join(temporary_directory, "exports/#{locale}/default.po")

    text =
      if File.exists?(input),
        do: File.read!(input),
        else: raise(RuntimeError, "Accent export has no #{locale} catalog")

    if text == "" do
      raise RuntimeError, "Accent export produced an empty #{locale} PO file"
    end

    lines = text |> String.split("\n", trim: false) |> remove_old_version_marker()

    catalog =
      lines
      |> Enum.join("\n")
      |> Expo.PO.parse_string!()

    pot = Expo.PO.parse_file!(@catalog)
    projected = Firmowid.Translations.catalog_for_source(pot, catalog, "default", locale)

    case Firmowid.Translations.validate_catalog(pot, projected, "default", locale) do
      :ok -> :ok
      {:error, message} -> raise RuntimeError, message
    end

    content = "# Accent version: #{version}\n" <> IO.iodata_to_binary(Expo.PO.compose(projected))

    write_catalog(
      Path.join(@root, "priv/gettext/#{locale}/LC_MESSAGES/default.po"),
      content,
      temporary_directory
    )
  end

  defp write_catalog(output, content, temporary_directory) do
    temporary_output = Path.join(temporary_directory, "catalog.po")

    File.mkdir_p!(Path.dirname(output))
    File.write!(temporary_output, content)
    File.rename!(temporary_output, output)
  end

  defp remove_old_version_marker(lines), do: Enum.reject(lines, &Regex.match?(@version_marker, &1))
end

Firmowid.Translations.Accent.run(System.argv())

defmodule Firmowid.Translations do
  @moduledoc "Helpers and technical validation for the application's PO catalogs."

  @type key :: {String.t(), String.t() | nil, String.t(), String.t() | nil}

  @domains ["default"]
  @polish_plural_forms "nplurals=3; plural=(n==1 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);"

  @doc "Returns the domains supported by the application catalogs."
  @spec domains() :: [String.t()]
  def domains, do: @domains

  @doc "Returns the canonical Polish gettext plural rule used by local catalogs."
  @spec polish_plural_forms() :: String.t()
  def polish_plural_forms, do: @polish_plural_forms

  @doc "Builds the canonical identity key for an Expo message."
  @spec message_key(struct(), String.t()) :: key()
  def message_key(message, domain), do: {domain, text(message.msgctxt), text(message.msgid), plural_id(message)}

  @doc "Removes the gettext header message from a parsed catalog."
  @spec source_messages(struct()) :: [struct()]
  def source_messages(%Expo.Messages{messages: messages}), do: Enum.reject(messages, &header?/1)

  @doc "Returns whether an Expo message is the gettext header."
  @spec header?(struct()) :: boolean()
  def header?(message), do: List.first(message.msgid) == ""

  @doc "Returns the plural message identity, or nil for singular messages."
  @spec plural_id(struct()) :: String.t() | nil
  def plural_id(message), do: message |> Map.get(:msgid_plural) |> text()

  @doc "Converts Expo iodata text to a binary, preserving nil."
  @spec text(nil | String.t() | [String.t()]) :: String.t() | nil
  def text(nil), do: nil
  def text(value), do: IO.iodata_to_binary(value)

  @doc "Extracts named interpolation placeholders, ignoring repeated occurrences."
  @spec placeholders(String.t() | [String.t()]) :: MapSet.t(String.t())
  def placeholders(value) do
    value
    |> text()
    |> then(&Regex.scan(~r/%\{[a-zA-Z0-9_]+\}/, &1))
    |> List.flatten()
    |> MapSet.new()
  end

  @doc "Validates source and Polish PO catalogs using technical checks only."
  @spec validate_catalog(struct(), struct(), String.t()) :: :ok | {:error, String.t()}
  def validate_catalog(pot, po, domain) do
    with :ok <- validate_metadata(po, domain),
         {:ok, source} <- index_messages(pot, domain),
         {:ok, target} <- index_messages(po, domain),
         :ok <- validate_identity(source, target, domain) do
      Enum.reduce_while(source, :ok, fn {key, original}, :ok ->
        case validate_entry(original, Map.fetch!(target, key), domain) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  defp index_messages(catalog, domain) do
    messages = source_messages(catalog)
    keys = Enum.map(messages, &message_key(&1, domain))

    case Enum.find(Enum.frequencies(keys), fn {_key, count} -> count > 1 end) do
      nil -> {:ok, Map.new(messages, &{message_key(&1, domain), &1})}
      {key, _count} -> {:error, "duplicate PO identity in #{domain}: #{inspect(key)}"}
    end
  end

  defp validate_identity(source, target, domain) do
    if MapSet.new(Map.keys(source)) == MapSet.new(Map.keys(target)),
      do: :ok,
      else: {:error, "POT/PO identity mismatch for #{domain}"}
  end

  defp validate_entry(original, translated, domain) do
    if plural_id(original) do
      validate_plural_entry(original, translated, domain)
    else
      validate_singular_entry(original, translated, domain)
    end
  end

  defp validate_singular_entry(original, translated, domain) do
    value = text(translated.msgstr)

    cond do
      value in [nil, ""] ->
        {:error, "missing Polish translation in #{domain}: #{inspect(original.msgid)}"}

      placeholders(original.msgid) != placeholders(value) ->
        {:error, "placeholder mismatch in #{domain}: #{inspect(original.msgid)}"}

      true ->
        :ok
    end
  end

  defp validate_plural_entry(original, translated, domain) do
    values = translated.msgstr

    if not is_map(values) or values |> Map.keys() |> Enum.sort() != [0, 1, 2] do
      {:error, "Polish plural must have three forms: #{inspect(original.msgid)}"}
    else
      expected = [original.msgid, original.msgid_plural, original.msgid_plural]

      expected
      |> Enum.with_index()
      |> Enum.reduce_while(:ok, fn {source, index}, :ok ->
        value = text(Map.fetch!(values, index))

        cond do
          value in [nil, ""] ->
            {:halt, {:error, "missing Polish translation in #{domain}: #{inspect(original.msgid)}"}}

          placeholders(source) != placeholders(value) ->
            {:halt, {:error, "placeholder mismatch in #{domain}: #{inspect(original.msgid)}"}}

          true ->
            {:cont, :ok}
        end
      end)
    end
  end

  defp validate_metadata(%Expo.Messages{headers: headers}, domain) do
    metadata =
      headers
      |> text()
      |> String.split("\n")
      |> Enum.flat_map(fn line ->
        case String.split(line, ":", parts: 2) do
          [key, value] -> [{String.trim(key), String.trim(value)}]
          _ -> []
        end
      end)
      |> Map.new()

    cond do
      Map.get(metadata, "Language") != "pl" ->
        {:error, "invalid Polish catalog metadata for #{domain}"}

      normalize(Map.get(metadata, "Plural-Forms")) != normalize(@polish_plural_forms) ->
        {:error, "invalid Polish catalog metadata for #{domain}"}

      true ->
        :ok
    end
  end

  defp normalize(value), do: value |> to_string() |> String.replace(~r/\s+/, "")
end

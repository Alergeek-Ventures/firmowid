defmodule Firmowid.Ash.Invoicing.Services.ResendAdapter do
  @moduledoc """
  Custom Swoosh adapter for Resend.

  Forked from `Resend.Swoosh.Adapter` to fix upstream issue #14:
  `Resend.Emails.Attachment` uses `@derive Jason.Encoder`, which serialises
  `nil` fields as `null`. The Resend API rejects `"content_id": null`,
  requiring the field to be absent entirely when unused.

  This adapter returns plain maps instead of structs for attachments,
  omitting nil keys. Original repo has been unmaintained for 6+ months
  (https://github.com/elixir-saas/resend-elixir/issues/14).
  """

  @behaviour Swoosh.Adapter

  @impl true
  def deliver(%Swoosh.Email{} = email, config) do
    Resend.Emails.send(Resend.client(config), %{
      subject: email.subject,
      from: format_sender(email.from),
      to: format_recipients(email.to),
      bcc: format_recipients(email.bcc),
      cc: format_recipients(email.cc),
      reply_to: format_recipients(email.reply_to),
      headers: email.headers,
      html: email.html_body,
      text: email.text_body,
      attachments: format_attachments(email.attachments)
    })
  end

  @impl true
  def deliver_many(list, config) do
    Enum.reduce_while(list, {:ok, []}, fn email, {:ok, acc} ->
      case deliver(email, config) do
        {:ok, email} ->
          {:cont, {:ok, acc ++ [email]}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  @impl true
  def validate_config(config) do
    Resend.validate_config!(config)
    :ok
  end

  defp format_attachment(%Swoosh.Attachment{} = attachment) do
    base_attachment = %{
      content: Swoosh.Attachment.get_content(attachment, :base64),
      content_type: attachment.content_type,
      filename: attachment.filename
    }

    if attachment.cid do
      Map.put(base_attachment, :content_id, attachment.cid)
    else
      base_attachment
    end
  end

  defp format_attachments(nil), do: nil
  defp format_attachments(attachments), do: Enum.map(attachments, &format_attachment/1)

  defp format_sender(nil), do: nil
  defp format_sender(from) when is_binary(from), do: from
  defp format_sender({"", from}), do: from
  defp format_sender({from_name, from}), do: "#{from_name} <#{from}>"

  defp format_recipients(nil), do: nil
  defp format_recipients(to) when is_binary(to), do: to
  defp format_recipients({_ignore, to}), do: to
  defp format_recipients(xs) when is_list(xs), do: Enum.map(xs, &format_recipients/1)
end

---
name: firmowid-mcp
description: Connect to a person's Firmowid account through the Firmowid MCP server to read and prepare invoices, check KSeF, match bank transactions and track work time. Use when a user asks to work with their Firmowid data.
---

# Firmowid MCP

Firmowid is a Polish business app for invoicing with KSeF, bank reconciliation, time tracking and leave requests. Its MCP server works on behalf of a person who has a Firmowid account.

## Connect

1. Add the MCP server `https://firmowid.pl/mcp` (Streamable HTTP).
2. Authorize with OAuth 2.1 (authorization code with S256 PKCE, scope `mcp`). Discovery starts at https://firmowid.pl/.well-known/oauth-protected-resource/mcp. Clients register with a Client ID Metadata Document or Dynamic Client Registration.
3. The person picks the organization to work in on the consent screen. Every tool call acts in that organization with that person's permissions.

## Work with it

- List the tools after connecting. The tool list and the server instructions returned by `initialize` are authoritative; follow them over this summary.
- Invoices sent to KSeF are always previewed and confirmed by the person inside the confirmation widget. Do not try to issue them another way.
- Never ask for KSeF tokens, passwords, certificates or private keys in chat.
- Propose bank transaction matches, and connect only the ones the person approves.

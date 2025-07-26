#!/usr/bin/env zsh

# Change to the project directory so ASDF activates the right Elixir version
cd /var/home/kosciak/projects/alergeek/firmowid || exit 1

# Set required Livebook connection info
export LIVEBOOK_NODE="livebook_prunzom4@127.0.0.1"
export LIVEBOOK_COOKIE="abc123"

# Run the escript using the ASDF-managed version of Elixir
/var/home/kosciak/.asdf/installs/elixir/1.18.4/.mix/escripts/livebook_tools mcp_server
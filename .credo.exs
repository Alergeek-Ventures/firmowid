%{
  configs: [
    %{
      name: "default",
      requires: ["./checks/*.ex"],
      checks: [
        {Checks.RejectDirectHistoryRates, []}
      ]
    }
  ]
}

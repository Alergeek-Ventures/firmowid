%{
  configs: [
    %{
      name: "default",
      requires: ["./checks/*.ex"],
      checks: [
        {Checks.RejectDirectHistoryRates, []},
        # TODOs are tracked as issues, not enforced in code
        {Credo.Check.Design.TagTODO, false},
        {Credo.Check.Design.TagFIXME, false}
      ]
    }
  ]
}

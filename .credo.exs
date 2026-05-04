%{
  configs: [
    %{
      name: "default",
      checks: %{
        extra: Enum.map(ExSlop.checks(), &{&1, []})
      }
    }
  ]
}

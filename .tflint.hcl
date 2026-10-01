# .pre-commit-config.yaml runs tflint with an explicit --only allowlist of terraform ruleset rules,
# so the preset below only matters for rules added to that list.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

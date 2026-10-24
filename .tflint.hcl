# Repo-wide tflint configuration, used by the pre-commit terraform_tflint hook and by CI.
#   tflint --init                      # once; downloads the plugins below
#   tflint --recursive --config "$PWD/.tflint.hcl"
# Plugin versions change often: check the tflint-ruleset-aws releases page before bumping.
# W09 keeps its own copy (modules/W09-terraform-foundations/terraform/.tflint.hcl)
# so the module can be linted on its own.

config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

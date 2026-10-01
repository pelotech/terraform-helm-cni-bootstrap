output "release_name" {
  description = "Name of the Helm release, null when create = false."
  value       = one(helm_release.cni[*].name)
}

output "namespace" {
  description = "Namespace of the Helm release."
  value       = var.namespace
}

output "resolved_version" {
  description = "Chart version installed, after chart_version and the module default."
  value       = local.version
}

output "resolved_set" {
  description = "Helm --set values installed: module defaults, then helm_set."
  value       = local.set
}

output "resolved_values" {
  description = "Helm values documents installed: module defaults, then helm_values."
  value       = local.values
}

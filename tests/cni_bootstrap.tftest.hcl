# Validates per-CNI chart resolution and --set merging without a live cluster.

mock_provider "helm" {}

variables {
  cluster_name = "test"
  region       = "us-west-2"
  service_cidr = "10.100.0.0/16"
}

run "cilium_defaults" {
  command = plan

  variables {
    cni              = "cilium"
    k8s_service_host = "api.example.com"
  }

  # No version literal here or in the other default runs: Renovate bumps the chart default in
  # main.tf but not this file, so a literal goes stale. Version resolution is covered by
  # cilium_chart_version_and_bootstrap_generation.
  assert {
    condition     = helm_release.cni[0].chart == "cilium" && helm_release.cni[0].version != ""
    error_message = "cilium must resolve to the cilium chart at the default version"
  }
  assert {
    condition     = length(terraform_data.wait_for_nodes) == 0
    error_message = "cilium must install concurrently (no node-registration gate)"
  }
  assert {
    condition     = helm_release.cni[0].atomic == true && helm_release.cni[0].cleanup_on_fail == true && helm_release.cni[0].replace == false
    error_message = "defaults must be atomic + cleanup_on_fail on, replace off"
  }
  assert {
    condition     = anytrue([for s in output.resolved_set : s.name == "kubeProxyReplacement" && s.value == "true"])
    error_message = "cilium must enable kubeProxyReplacement by default"
  }
  assert {
    condition     = anytrue([for s in output.resolved_set : s.name == "k8sServiceHost" && s.value == "api.example.com"])
    error_message = "cilium with kube-proxy replacement must set k8sServiceHost from k8s_service_host"
  }
  assert {
    condition     = !anytrue([for s in output.resolved_set : s.name == "cniBootstrapGeneration"])
    error_message = "empty bootstrap_generation must not add the forcing set value"
  }
}

run "cilium_without_kube_proxy_replacement_omits_api_host" {
  command = plan

  variables {
    cni                    = "cilium"
    kube_proxy_replacement = false
    k8s_service_host       = "api.example.com"
  }

  assert {
    condition     = !anytrue([for s in output.resolved_set : s.name == "k8sServiceHost"])
    error_message = "k8sServiceHost must not be set when kube_proxy_replacement is false"
  }
}

run "cilium_chart_version_and_bootstrap_generation" {
  command = plan

  variables {
    cni                  = "cilium"
    chart_version        = "1.16.1"
    bootstrap_generation = "42"
  }

  assert {
    condition     = output.resolved_version == "1.16.1" && helm_release.cni[0].version == "1.16.1"
    error_message = "chart_version must override the built-in default"
  }
  assert {
    condition     = anytrue([for s in output.resolved_set : s.name == "cniBootstrapGeneration" && s.value == "42"])
    error_message = "bootstrap_generation must add an inert set value that forces a helm re-apply on bump"
  }
}

run "kube_ovn_defaults" {
  command = plan

  variables {
    cni          = "kube-ovn"
    service_cidr = "172.20.0.0/16"
  }

  assert {
    condition     = helm_release.cni[0].name == "kube-ovn" && helm_release.cni[0].chart == "kube-ovn" && helm_release.cni[0].repository == "oci://ghcr.io/pelotech/charts" && helm_release.cni[0].version != ""
    error_message = "kube-ovn must resolve to the OCI pelotech kube-ovn chart at the default version"
  }
  assert {
    condition     = helm_release.cni[0].timeout == 900
    error_message = "kube-ovn must default to the 15m (900s) timeout"
  }
  assert {
    condition     = yamldecode(output.resolved_values[0]).ipv4.SVC_CIDR == "172.20.0.0/16"
    error_message = "kube-ovn must set ipv4.SVC_CIDR from service_cidr in its default values document"
  }
  assert {
    condition     = yamldecode(output.resolved_values[0]).MASTER_NODES_LABEL == "kube-ovn/role=master"
    error_message = "kube-ovn must set MASTER_NODES_LABEL from the node selector in its default values document"
  }
  # The v1 chart reads pinger resources from kube-ovn-pinger (a bare `pinger` key is a silent no-op).
  assert {
    condition     = yamldecode(output.resolved_values[0])["kube-ovn-pinger"].limits.memory == "300Mi"
    error_message = "kube-ovn must size the pinger via the chart's kube-ovn-pinger key"
  }
  assert {
    condition     = length(terraform_data.wait_for_nodes) == 1
    error_message = "kube-ovn must gate the install on node registration"
  }
}

run "kube_ovn_v2_defaults" {
  command = plan

  variables {
    cni         = "kube-ovn-v2"
    helm_values = ["controller:\n  metrics:\n    port: 12345\n"]
  }

  assert {
    condition     = helm_release.cni[0].name == "kube-ovn" && helm_release.cni[0].chart == "kube-ovn-v2" && helm_release.cni[0].repository == "oci://ghcr.io/kubeovn/charts" && helm_release.cni[0].version != ""
    error_message = "kube-ovn-v2 must resolve to the upstream OCI kube-ovn-v2 chart under the kube-ovn release name"
  }
  assert {
    condition     = helm_release.cni[0].timeout == 900
    error_message = "kube-ovn-v2 must default to the 15m (900s) timeout"
  }
  assert {
    condition     = yamldecode(output.resolved_values[0]).networking.services.cidr.v4 == "10.100.0.0/16"
    error_message = "kube-ovn-v2 must set networking.services.cidr.v4 from service_cidr"
  }
  assert {
    condition     = yamldecode(output.resolved_values[0]).masterNodesLabels["kube-ovn/role"] == "master"
    error_message = "kube-ovn-v2 must derive masterNodesLabels from the node selector"
  }
  # kube-ovn-controller must land on the dedicated CNI node alongside ovn-central.
  assert {
    condition = yamldecode(output.resolved_values[0]).controller.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].matchExpressions[0] == {
      key      = "kube-ovn/role"
      operator = "In"
      values   = ["master"]
    }
    error_message = "kube-ovn-v2 must pin kube-ovn-controller to the master-labeled CNI node"
  }
  assert {
    condition     = length(output.resolved_values) == 2 && yamldecode(output.resolved_values[1]).controller.metrics.port == 12345
    error_message = "caller helm_values must append after the module's default values document (so they win on merge)"
  }
  assert {
    condition     = length(terraform_data.wait_for_nodes) == 1
    error_message = "kube-ovn-v2 must gate the install on node registration"
  }
}

run "kube_ovn_v2_selector_override_drives_master_label" {
  command = plan

  variables {
    cni                     = "kube-ovn-v2"
    wait_for_nodes_selector = "cni/dedicated=true"
  }

  assert {
    condition     = yamldecode(output.resolved_values[0]).masterNodesLabels["cni/dedicated"] == "true"
    error_message = "an overridden selector must drive masterNodesLabels"
  }
  assert {
    condition = yamldecode(output.resolved_values[0]).controller.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].matchExpressions[0] == {
      key      = "cni/dedicated"
      operator = "In"
      values   = ["true"]
    }
    error_message = "an overridden selector must drive the controller node affinity"
  }
}

run "kube_ovn_v2_non_kv_selector_omits_node_affinity" {
  command = plan

  variables {
    cni                     = "kube-ovn-v2"
    wait_for_nodes_selector = "a=b,c=d"
  }

  # A selector that is not a single key=value cannot map to a label, so the values
  # document must omit masterNodesLabels and controller.nodeAffinity. The chart's
  # node-affinity defaults then apply while the controller resource defaults stay.
  assert {
    condition     = !can(yamldecode(output.resolved_values[0]).masterNodesLabels)
    error_message = "a non key=value selector must not render masterNodesLabels"
  }
  assert {
    condition     = !can(yamldecode(output.resolved_values[0]).controller.nodeAffinity)
    error_message = "a non key=value selector must not render the controller affinity"
  }
}

run "kube_ovn_requires_service_cidr" {
  command = plan

  variables {
    cni          = "kube-ovn"
    service_cidr = ""
  }

  expect_failures = [var.service_cidr]
}

run "kube_ovn_requires_cluster_name" {
  command = plan

  variables {
    cni          = "kube-ovn"
    cluster_name = ""
  }

  expect_failures = [var.cluster_name]
}

run "kube_ovn_requires_region" {
  command = plan

  variables {
    cni    = "kube-ovn"
    region = ""
  }

  expect_failures = [var.region]
}

run "kube_ovn_wait_disabled" {
  command = plan

  variables {
    cni            = "kube-ovn"
    wait_for_nodes = false
  }

  assert {
    condition     = length(terraform_data.wait_for_nodes) == 0
    error_message = "wait_for_nodes=false must disable the node-registration gate"
  }
}

run "custom_can_enable_wait_for_nodes" {
  command = plan

  variables {
    cni                     = "custom"
    wait_for_nodes          = true
    wait_for_nodes_selector = "node-role.kubernetes.io/cni=true"
    custom_chart = {
      repository = "https://example.com/charts"
      chart      = "my-cni"
      version    = "0.1.0"
    }
  }

  assert {
    condition     = length(terraform_data.wait_for_nodes) == 1
    error_message = "a custom CNI must be able to opt into the node-registration gate"
  }
}

run "custom_chart" {
  command = plan

  variables {
    cni = "custom"
    custom_chart = {
      repository = "https://example.com/charts"
      chart      = "my-cni"
      version    = "0.1.0"
    }
  }

  assert {
    condition     = helm_release.cni[0].chart == "my-cni" && helm_release.cni[0].version == "0.1.0" && helm_release.cni[0].repository == "https://example.com/charts"
    error_message = "custom must use the custom_chart coordinates"
  }

  assert {
    condition     = helm_release.cni[0].name == "my-cni"
    error_message = "release name must fall back to the chart name when release_name is omitted"
  }
}

run "custom_chart_release_name" {
  command = plan

  variables {
    cni = "custom"
    custom_chart = {
      repository   = "https://example.com/charts"
      chart        = "my-cni"
      version      = "0.1.0"
      release_name = "cni"
    }
  }

  assert {
    condition     = helm_release.cni[0].name == "cni"
    error_message = "release_name must override the chart-derived release name"
  }

  # The rest of the coordinates must be untouched by naming the release.
  assert {
    condition     = helm_release.cni[0].chart == "my-cni"
    error_message = "release_name must not change which chart is installed"
  }
}

run "custom_requires_chart" {
  command = plan

  variables {
    cni = "custom"
  }

  expect_failures = [var.custom_chart]
}

run "create_false_installs_nothing" {
  command = plan

  variables {
    create = false
  }

  assert {
    condition     = length(helm_release.cni) == 0
    error_message = "create=false must install no helm release"
  }
}

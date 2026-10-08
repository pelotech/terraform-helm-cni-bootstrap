# RKE2 clusters: client certificate authentication for the node poll and the RKE2 CNI defaults.

mock_provider "helm" {}

run "rke2_on_azure_turns_kube_proxy_replacement_on_without_aksbyocni" {
  command = plan
  variables {
    cloud            = "azure"
    distribution     = "rke2"
    pod_cidr         = "10.244.0.0/16"
    k8s_service_host = "127.0.0.1"
    k8s_service_port = "6443"
  }
  assert {
    condition     = yamldecode(output.resolved_values[0]).kubeProxyReplacement == true && yamldecode(output.resolved_values[0]).k8sServiceHost == "127.0.0.1" && yamldecode(output.resolved_values[0]).k8sServicePort == "6443"
    error_message = "rke2 defaults kube-proxy replacement on and uses the given host and port"
  }
  assert {
    condition     = !contains(keys(yamldecode(output.resolved_values[0])), "aksbyocni")
    error_message = "aksbyocni is an AKS setting, not an RKE2 one"
  }
}

run "a_selector_from_the_stack_turns_the_poll_on" {
  command = plan
  variables {
    cloud                   = "azure"
    distribution            = "rke2"
    pod_cidr                = "10.244.0.0/16"
    cluster_endpoint        = "https://api.example:6443"
    cluster_ca_certificate  = "Y2E="
    client_certificate      = "Y2VydA=="
    client_key              = "a2V5"
    wait_for_nodes_selector = "node-role.kubernetes.io/control-plane=true"
    wait_for_nodes_count    = 3
  }
  assert {
    condition     = length(terraform_data.wait_for_nodes) == 1
    error_message = "cilium has no selector of its own, so the one the stack passes must start the poll"
  }
}

run "kube_ovn_with_an_empty_selector_still_polls" {
  command = plan
  variables {
    cloud                   = "aws"
    cni                     = "kube-ovn-v2"
    service_cidr            = "10.100.0.0/16"
    cluster_name            = "test"
    region                  = "us-west-2"
    wait_for_nodes_selector = ""
  }
  assert {
    condition     = length(terraform_data.wait_for_nodes) == 1
    error_message = "an empty selector with kube-ovn keeps the documented behaviour: the poll waits for any node"
  }
}

run "an_empty_selector_keeps_the_poll_off" {
  command = plan
  variables {
    cloud                   = "azure"
    pod_cidr                = "10.244.0.0/16"
    wait_for_nodes_selector = ""
  }
  assert {
    condition     = length(terraform_data.wait_for_nodes) == 0
    error_message = "AKS passes an empty selector for cilium and must keep its no-poll behaviour"
  }
}

run "client_certificate_renders_into_the_poll_kubeconfig" {
  command = plan
  variables {
    cni                    = "kube-ovn-v2"
    service_cidr           = "10.96.0.0/16"
    cluster_endpoint       = "https://api.example:6443"
    cluster_ca_certificate = "Y2E="
    client_certificate     = "Y2VydA=="
    client_key             = "a2V5"
  }
  assert {
    condition     = yamldecode(terraform_data.wait_for_nodes[0].input).users[0].user["client-certificate-data"] == "Y2VydA==" && !contains(keys(yamldecode(terraform_data.wait_for_nodes[0].input).users[0].user), "exec")
    error_message = "the poll authenticates with the client certificate when there is no exec plugin"
  }
}

run "endpoint_needs_a_credential" {
  command = plan
  variables {
    cluster_endpoint       = "https://api.example:6443"
    cluster_ca_certificate = "Y2E="
  }
  expect_failures = [var.cluster_endpoint]
}

run "distribution_must_be_known" {
  command = plan
  variables {
    distribution = "k3s"
  }
  expect_failures = [var.distribution]
}

run "the_managed_distribution_follows_the_cloud" {
  command = plan
  variables {
    cloud    = "azure"
    pod_cidr = "10.244.0.0/16"
  }
  assert {
    condition     = yamldecode(output.resolved_values[0]).aksbyocni.enabled == true && yamldecode(output.resolved_values[0]).kubeProxyReplacement == false
    error_message = "azure without a distribution means aks"
  }
}

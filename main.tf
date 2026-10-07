locals {
  kube_ovn_master_label  = "kube-ovn/role=master"
  distribution           = coalesce(var.distribution, { aws = "eks", azure = "aks" }[var.cloud])
  kube_proxy_replacement = coalesce(var.kube_proxy_replacement, local.distribution != "aks")

  # What each cni value installs. set is the module's default --set list; values_template its default values file.
  # node_selector is the label the node poll waits on; empty means no poll unless wait_for_nodes = true.
  cni_profiles = {
    cilium = {
      release_name = "cilium"
      repository   = "https://helm.cilium.io/"
      chart        = "cilium"
      # renovate: datasource=helm depName=cilium registryUrl=https://helm.cilium.io
      version            = "1.20.2"
      timeout            = 600
      node_selector      = ""
      needs_service_cidr = false
      values_template    = null
      set = concat(
        [
          { name = "kubeProxyReplacement", value = tostring(local.kube_proxy_replacement) },
          { name = "hubble.relay.enabled", value = "true" },
          { name = "hubble.ui.enabled", value = "true" },
        ],
        local.kube_proxy_replacement && var.k8s_service_host != "" ? [
          { name = "k8sServiceHost", value = var.k8s_service_host },
          { name = "k8sServicePort", value = var.k8s_service_port },
        ] : [],
        local.distribution == "aks" ? [{ name = "aksbyocni.enabled", value = "true" }] : [],
        var.pod_cidr != "" ? [{ name = "ipam.operator.clusterPoolIPv4PodCIDRList", value = "{${var.pod_cidr}}" }] : [],
      )
    }
    "kube-ovn" = {
      release_name = "kube-ovn"
      repository   = "oci://ghcr.io/pelotech/charts"
      chart        = "kube-ovn"
      # renovate: datasource=docker depName=ghcr.io/pelotech/charts/kube-ovn
      version            = "v1.13.9"
      timeout            = 900
      node_selector      = local.kube_ovn_master_label
      needs_service_cidr = true
      values_template    = "kube-ovn.yaml.tftpl"
      set                = []
    }
    "kube-ovn-v2" = {
      # Same release name as kube-ovn, so switching between the two upgrades in place.
      release_name = "kube-ovn"
      repository   = "oci://ghcr.io/kubeovn/charts"
      chart        = "kube-ovn-v2"
      # renovate: datasource=docker depName=ghcr.io/kubeovn/charts/kube-ovn-v2
      version            = "v1.16.10"
      timeout            = 900
      node_selector      = local.kube_ovn_master_label
      needs_service_cidr = true
      values_template    = "kube-ovn-v2.yaml.tftpl"
      set                = []
    }
    custom = {
      release_name       = try(coalesce(var.custom_chart.release_name, var.custom_chart.chart), null)
      repository         = try(var.custom_chart.repository, null)
      chart              = try(var.custom_chart.chart, null)
      version            = try(var.custom_chart.version, null)
      timeout            = 600
      node_selector      = ""
      needs_service_cidr = false
      values_template    = null
      set                = []
    }
  }
  cni_profile = local.cni_profiles[var.cni]

  # The poll runs for the profiles that need it, and whenever a stack passes a selector, such as RKE2's control-plane label.
  node_selector  = var.wait_for_nodes_selector != null ? var.wait_for_nodes_selector : local.cni_profile.node_selector
  wait_for_nodes = coalesce(var.wait_for_nodes, local.cni_profile.node_selector != "" || local.node_selector != "")
  # kube-ovn pins its control plane to the same label the poll waits on. The v2 chart needs it split into key and value.
  master_label = try(regex("^([^=]+)=([^=]*)$", local.node_selector), ["", ""])

  version = coalesce(var.chart_version, local.cni_profile.version)
  values = concat(
    local.cni_profile.values_template == null ? [] : [templatefile("${path.module}/values/${local.cni_profile.values_template}", {
      service_cidr       = var.service_cidr
      pod_cidr           = var.pod_cidr
      pod_gateway        = var.pod_cidr != "" ? cidrhost(var.pod_cidr, 1) : ""
      master_nodes_label = local.node_selector
      master_label_key   = local.master_label[0]
      master_label_value = local.master_label[1]
    })],
    var.helm_values,
  )
  set = concat(
    local.cni_profile.set,
    # Inert chart key; a new bootstrap_generation forces a helm upgrade.
    var.bootstrap_generation != "" ? [{ name = "cniBootstrapGeneration", value = var.bootstrap_generation }] : [],
    var.helm_set,
  )
}

locals {
  # With kube_exec or a client certificate the poll gets a rendered kubeconfig; without either, it falls back to the AWS CLI.
  poll_has_credential = var.kube_exec != null || (var.client_certificate != "" && var.client_key != "")
  poll_uses_aws_cli   = local.wait_for_nodes && !local.poll_has_credential
  poll_kubeconfig = !local.poll_has_credential ? "" : yamlencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [{
      name = "cluster"
      cluster = {
        server                       = var.cluster_endpoint
        "certificate-authority-data" = var.cluster_ca_certificate
      }
    }]
    users = [{
      name = "user"
      # Two merges, because a conditional cannot return objects of different shapes.
      user = merge(
        var.kube_exec == null ? {} : {
          exec = {
            apiVersion         = var.kube_exec.api_version
            command            = var.kube_exec.command
            args               = var.kube_exec.args
            env                = [for k, v in var.kube_exec.env : { name = k, value = v }]
            interactiveMode    = "Never"
            provideClusterInfo = false
          }
        },
        var.kube_exec != null ? {} : {
          "client-certificate-data" = var.client_certificate
          "client-key-data"         = var.client_key
        },
      )
    }]
    contexts          = [{ name = "cluster", context = { cluster = "cluster", user = "user" } }]
    "current-context" = "cluster"
  })
}

moved {
  from = terraform_data.wait_nodes
  to   = terraform_data.wait_for_nodes
}

# Depends only on cluster inputs, so it runs in parallel with node creation.
resource "terraform_data" "wait_for_nodes" {
  count = var.create && local.wait_for_nodes ? 1 : 0

  # The kubeconfig is recorded so a plan shows what the poll connects with. With a client certificate it holds the key, which the stack's own state already carries.
  input            = local.poll_kubeconfig
  triggers_replace = [var.bootstrap_generation, var.cluster_endpoint, var.cluster_name, var.region, local.node_selector, var.wait_for_nodes_count]

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/wait-for-nodes.sh"
    environment = {
      KUBECONFIG_CONTENT = local.poll_kubeconfig
      CLUSTER_NAME       = var.cluster_name
      REGION             = var.region
      SELECTOR           = local.node_selector
      COUNT              = tostring(var.wait_for_nodes_count)
      TIMEOUT            = tostring(var.wait_for_nodes_timeout)
    }
  }
}

resource "helm_release" "cni" {
  count      = var.create ? 1 : 0
  name       = local.cni_profile.release_name
  repository = local.cni_profile.repository
  chart      = local.cni_profile.chart
  version    = local.version
  namespace  = var.namespace
  timeout    = coalesce(var.wait_timeout, local.cni_profile.timeout)

  atomic          = var.atomic
  cleanup_on_fail = var.cleanup_on_fail
  replace         = var.replace

  set    = local.set
  values = local.values

  depends_on = [terraform_data.wait_for_nodes]
}

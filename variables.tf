variable "create" {
  type        = bool
  default     = true
  description = "Installs the CNI Helm release. Set false to create nothing."
}

variable "cni" {
  type        = string
  default     = "cilium"
  description = "CNI to install: cilium, kube-ovn (v1 chart), kube-ovn-v2 or custom. custom installs the chart in custom_chart."

  validation {
    condition     = contains(["cilium", "kube-ovn", "kube-ovn-v2", "custom"], var.cni)
    error_message = "cni must be one of: cilium, kube-ovn, kube-ovn-v2, custom."
  }
}

variable "namespace" {
  type        = string
  default     = "kube-system"
  description = "Namespace of the Helm release."
}

variable "cloud" {
  type        = string
  default     = "aws"
  description = "Cloud the cluster runs on: aws or azure. Sets the CNI defaults that differ per cloud."

  validation {
    condition     = contains(["aws", "azure"], var.cloud)
    error_message = "cloud must be one of: aws, azure."
  }
}

variable "cluster_endpoint" {
  type        = string
  default     = ""
  description = "API server URL, for the node poll. Set it together with cluster_ca_certificate and kube_exec to poll without a cloud CLI."

  validation {
    condition     = (var.cluster_endpoint != "") == (var.cluster_ca_certificate != "") && (var.cluster_endpoint != "") == (var.kube_exec != null)
    error_message = "cluster_endpoint, cluster_ca_certificate and kube_exec must be set together."
  }
}

variable "cluster_ca_certificate" {
  type        = string
  default     = ""
  description = "Base64 encoded cluster CA certificate, for the node poll."
}

variable "kube_exec" {
  type = object({
    api_version = string
    command     = string
    args        = optional(list(string), [])
    env         = optional(map(string), {})
  })
  default     = null
  description = "Exec credential plugin the node poll authenticates with. Same shape as the helm provider's kubernetes.exec."
}

variable "pod_cidr" {
  type        = string
  default     = ""
  description = "Pod CIDR the CNI allocates from. Required on azure, where AKS routes to it; leave empty on aws."

  validation {
    condition     = var.cloud != "azure" || var.cni == "custom" || var.pod_cidr != ""
    error_message = "pod_cidr is required on azure for cilium, kube-ovn and kube-ovn-v2."
  }
}

variable "cluster_name" {
  type        = string
  default     = ""
  description = "Name of the EKS cluster, for the node poll's AWS CLI fallback. Required when wait_for_nodes is true and kube_exec is not set."

  validation {
    # try: an unknown cni fails its own validation instead of this one.
    condition     = !try(local.poll_uses_aws_cli, false) || var.cluster_name != ""
    error_message = "cluster_name is required when waiting for nodes without kube_exec."
  }
}

variable "region" {
  type        = string
  default     = ""
  description = "AWS region of the cluster, for the node poll's AWS CLI fallback. Required when wait_for_nodes is true and kube_exec is not set."

  validation {
    condition     = !try(local.poll_uses_aws_cli, false) || var.region != ""
    error_message = "region is required when waiting for nodes without kube_exec."
  }
}

variable "k8s_service_host" {
  type        = string
  default     = ""
  description = "API server host without scheme, for Cilium kube-proxy replacement. Ignored unless cni = cilium and kube_proxy_replacement is true."
}

variable "service_cidr" {
  type        = string
  default     = ""
  description = "Service CIDR of the cluster, passed to the kube-ovn charts. Required for kube-ovn and kube-ovn-v2."

  validation {
    condition     = !try(local.cni_profile.needs_service_cidr, false) || var.service_cidr != ""
    error_message = "service_cidr is required for kube-ovn and kube-ovn-v2."
  }
}

variable "kube_proxy_replacement" {
  type        = bool
  default     = null
  description = "Turns on Cilium kube-proxy replacement. null means true on aws and false on azure, where kube-proxy stays on. When true, k8s_service_host sets k8sServiceHost and k8sServicePort."
}

variable "chart_version" {
  type        = string
  default     = null
  description = "Chart version to install. null uses the module default for the selected cni; ignored for custom, which uses custom_chart.version."
}

variable "helm_set" {
  type        = list(object({ name = string, value = string }))
  default     = []
  description = "Extra Helm --set values, applied after the module defaults."
}

variable "helm_values" {
  type        = list(string)
  default     = []
  description = "Extra Helm values documents, applied after the module defaults."
}

variable "wait_timeout" {
  type        = number
  default     = null
  description = "Seconds Helm waits for the release to become ready. null uses the module default for the selected cni."
}

variable "atomic" {
  type        = bool
  default     = true
  description = "Rolls back a failed install or upgrade (helm --atomic). Set false only to debug a failed release."
}

variable "cleanup_on_fail" {
  type        = bool
  default     = true
  description = "Deletes resources created during a failed upgrade (helm --cleanup-on-fail)."
}

variable "replace" {
  type        = bool
  default     = false
  description = "Reuses the name of a failed or pending release (helm install --replace). Set true for one apply to repair a stuck release, then set it back."
}

variable "bootstrap_generation" {
  type        = string
  default     = ""
  description = "Change this value to run the node poll and the Helm upgrade again, for example after you replace the master node. Change it only after the old master node is gone."
}

variable "wait_for_nodes" {
  type        = bool
  default     = null
  description = "Waits for nodes to register before the install. null means true for kube-ovn and kube-ovn-v2, false otherwise."
}

variable "wait_for_nodes_selector" {
  type        = string
  default     = null
  description = "Label the node poll waits on, and the label kube-ovn pins its control plane to. null uses the module default for the selected cni; empty waits for any node."
}

variable "wait_for_nodes_count" {
  type        = number
  default     = 1
  description = "Number of matching nodes the poll waits for. Set it to the size of your CNI node pool."
}

variable "wait_for_nodes_timeout" {
  type        = number
  default     = 600
  description = "Seconds the node poll waits before it fails."
}

variable "custom_chart" {
  type = object({
    repository   = string
    chart        = string
    version      = string
    release_name = optional(string)
  })
  default     = null
  description = "Chart to install when cni = custom. release_name defaults to the chart name; changing it later replaces the release."

  validation {
    condition     = var.cni != "custom" || var.custom_chart != null
    error_message = "custom_chart is required when cni = custom."
  }
}

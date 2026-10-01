# terraform-helm-cni-bootstrap

Installs a Kubernetes CNI with Helm during `terraform apply`, so the nodes of a cluster created without a CNI
become `Ready`. Supported `cni` values: `cilium`, `kube-ovn`, `kube-ovn-v2` and `custom`.

## Requirements

- Terraform 1.9 or later and the helm provider 3.0 or later.
- A `helm` provider configured by you. The module configures no providers.
- `kubectl` and your cluster's credential plugin (`aws` or `kubelogin`) on the host that applies, for the kube-ovn
  node poll. With `cluster_endpoint`, `cluster_ca_certificate` and `kube_exec` set, the poll builds its own
  kubeconfig. Without them it falls back to `aws eks update-kubeconfig` and needs `cluster_name` and `region`.

## Quick start

Configure the helm provider from your cluster module, then call this module.

AWS, with `github.com/pelotech/terraform-foundation-aws-stack`:

```hcl
provider "helm" {
  kubernetes = {
    host                   = module.foundation.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.foundation.eks_cluster_certificate_authority_data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.foundation.eks_cluster_name]
    }
  }
}

module "cni_bootstrap" {
  source           = "github.com/pelotech/terraform-helm-cni-bootstrap?ref=<release tag>"
  cni              = "cilium"
  k8s_service_host = module.foundation.cilium_k8s_service_host
}
```

Azure, with `github.com/pelotech/terraform-azure-foundation`:

```hcl
provider "helm" {
  kubernetes = {
    host                   = module.stack.cluster_endpoint
    cluster_ca_certificate = base64decode(module.stack.cluster_ca_certificate)
    exec                   = module.stack.kube_exec
  }
}

module "cni_bootstrap" {
  source                  = "github.com/pelotech/terraform-helm-cni-bootstrap?ref=<release tag>"
  cloud                   = module.stack.cloud
  cni                     = "kube-ovn-v2"
  cluster_endpoint        = module.stack.cluster_endpoint
  cluster_ca_certificate  = module.stack.cluster_ca_certificate
  kube_exec               = module.stack.kube_exec
  k8s_service_host        = module.stack.cluster_api_host
  service_cidr            = module.stack.cluster_service_cidr
  pod_cidr                = module.stack.cluster_pod_cidr
  wait_for_nodes_count    = module.stack.cni_node_size
  wait_for_nodes_selector = module.stack.cni_node_selector
}
```

Each stack output maps to one input:

| Stack output             | Input                     |
| ------------------------ | ------------------------- |
| `cloud`                  | `cloud`                   |
| `cluster_endpoint`       | `cluster_endpoint`        |
| `cluster_ca_certificate` | `cluster_ca_certificate`  |
| `kube_exec`              | `kube_exec`               |
| `cluster_api_host`       | `k8s_service_host`        |
| `cluster_service_cidr`   | `service_cidr`            |
| `cluster_pod_cidr`       | `pod_cidr`                |
| `cni_node_size`          | `wait_for_nodes_count`    |
| `cni_node_selector`      | `wait_for_nodes_selector` |

## Choose a CNI

| `cni`         | Chart                                      | Release name                                      | Waits for nodes | Required inputs                                  |
| ------------- | ------------------------------------------ | ------------------------------------------------- | --------------- | ------------------------------------------------ |
| `cilium`      | `https://helm.cilium.io/` cilium           | `cilium`                                          | no              | `pod_cidr` on azure                              |
| `kube-ovn`    | `oci://ghcr.io/pelotech/charts/kube-ovn`   | `kube-ovn`                                        | yes             | `service_cidr`, a cluster connection, `pod_cidr` on azure |
| `kube-ovn-v2` | `oci://ghcr.io/kubeovn/charts/kube-ovn-v2` | `kube-ovn`                                        | yes             | `service_cidr`, a cluster connection, `pod_cidr` on azure |
| `custom`      | `custom_chart`                             | `custom_chart.release_name`, else the chart name  | no              | `custom_chart`                                   |

A cluster connection is `cluster_endpoint`, `cluster_ca_certificate` and `kube_exec` together, or `cluster_name` and
`region` for the AWS CLI fallback.

Run `terraform output resolved_version`, `resolved_set` and `resolved_values` to see what the module installs.

## How install order works

The module depends only on the cluster, so Terraform runs it in parallel with node creation. Do not add
`depends_on` on the node group: the install then waits for the node group, and node creation times out.

| CNI      | When it installs                                                      |
| -------- | --------------------------------------------------------------------- |
| cilium   | At once. The agent runs on `NotReady` nodes and makes them `Ready`.   |
| kube-ovn | After the node poll finds a node with label `kube-ovn/role=master`.  |

### cilium

`kube_proxy_replacement` is on by default on aws and off on azure, where kube-proxy stays on. When it is on, set
`k8s_service_host` to the API server host, without scheme, so Cilium reaches the API server without kube-proxy.
On azure the module also sets `aksbyocni.enabled`. With `pod_cidr`, Cilium allocates pods from that range. The module
turns on Hubble relay and UI; turn them off with `helm_set`.

### kube-ovn and kube-ovn-v2

```hcl
module "cni_bootstrap" {
  source       = "github.com/pelotech/terraform-helm-cni-bootstrap?ref=<release tag>"
  cni          = "kube-ovn-v2"
  cluster_name = module.foundation.eks_cluster_name
  region       = module.foundation.region
  service_cidr = module.foundation.eks_cluster_service_cidr
}
```

With `pod_cidr`, both charts take the pod CIDR and use its first address as the gateway.

Both variants install under the release name `kube-ovn`, so a switch between them is an in-place upgrade. Their
chart values differ, so `helm_set` and `helm_values` entries do not carry over.

The module pins the kube-ovn control plane to the node poll label, `kube-ovn/role=master` by default. On the v2
chart it sets `masterNodesLabels` and a node affinity on `kube-ovn-controller`. Set `wait_for_nodes_selector` to a
single `key=value` to change the label.

Module defaults for kube-ovn-v2:

| Component    | Setting                                                   |
| ------------ | --------------------------------------------------------- |
| `central`    | requests 1 CPU, 768Mi memory                              |
| `controller` | requests and limits 1536Mi memory                         |
| `agent`      | requests and limits 256Mi memory                          |
| `ovsOvn`     | requests and limits 512Mi memory                          |
| `ovsOvn`     | `RollingUpdate`, `maxSurge: 0`, `maxUnavailable: 1`       |
| `pinger`     | checks reach `8.8.8.8` and `google.com.`                  |

OVS pods update one node at a time. Pod networking on that node stops during the update. Override
`ovsOvn.updateStrategy` if your nodes have spare CPU for two OVS pods.

### custom

```hcl
module "cni_bootstrap" {
  source = "github.com/pelotech/terraform-helm-cni-bootstrap?ref=<release tag>"
  cni    = "custom"
  custom_chart = {
    repository   = "https://example.com/charts"
    chart        = "my-cni"
    version      = "1.2.3"
    release_name = "cni"
  }
  helm_set = [{ name = "some.value", value = "true" }]
}
```

A custom chart installs at once. If it needs registered nodes first, set `wait_for_nodes = true`,
`wait_for_nodes_selector` and a cluster connection.

Set `release_name` at the first install. A change replaces the release: Helm uninstalls the CNI and installs it again.

## Override chart values

- `chart_version` replaces the module's chart version.
- `helm_set` entries apply after the module's `--set` defaults.
- `helm_values` documents apply after the module's values document.

## Operations

### Adopt an existing release

If the cluster already has the CNI release, the first apply fails with:

```text
Error: installation failed
cannot re-use a name that is still in use
```

Do not uninstall the release: this removes the CNI. Do not set `replace`. Import the release, using the release name
from the table above and your `namespace`:

```bash
terraform import 'module.cni_bootstrap.helm_release.cni[0]' kube-system/kube-ovn
```

The next apply is an in-place `helm upgrade` to the module's chart and values. Before you run it:

1. Run `helm get values -n <namespace> <release>`. The upgrade does not keep existing values. Pass what you need
   through `helm_set` or `helm_values`.
2. Compare the chart source and version with the table above. A different chart is a migration, not a no-op.
3. For kube-ovn, check that a node with label `kube-ovn/role=master` is registered.

To move from `cni = "custom"` to `cni = "kube-ovn-v2"` on a cluster that already runs the kube-ovn-v2 chart:

1. Set `cni = "kube-ovn-v2"`.
2. Remove `custom_chart`.
3. Remove the `helm_set` and `helm_values` entries the module now sets.

### Repair a failed release

`atomic` and `cleanup_on_fail` are on by default. A failed install rolls back and does not block the release name.
If an apply still fails with `cannot re-use a name that is still in use`, run `helm list -A --all`:

| Release state         | Action                                                               |
| --------------------- | -------------------------------------------------------------------- |
| `failed` or `pending` | Set `replace = true` for one apply, or `helm uninstall` and apply.   |
| `deployed`            | Import the release. See "Adopt an existing release".                 |

### Replace the master node

1. Replace the master node in your cluster module, and wait until the old node is gone.
2. Change `bootstrap_generation` and apply. The node poll runs again and Helm upgrades the release, so kube-ovn
   reads the new master node IP.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | >= 3.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | >= 3.0.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.cni](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |
| [terraform_data.wait_for_nodes](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_atomic"></a> [atomic](#input\_atomic) | Rolls back a failed install or upgrade (helm --atomic). Set false only to debug a failed release. | `bool` | `true` | no |
| <a name="input_bootstrap_generation"></a> [bootstrap\_generation](#input\_bootstrap\_generation) | Change this value to run the node poll and the Helm upgrade again, for example after you replace the master node. Change it only after the old master node is gone. | `string` | `""` | no |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | Chart version to install. null uses the module default for the selected cni; ignored for custom, which uses custom\_chart.version. | `string` | `null` | no |
| <a name="input_cleanup_on_fail"></a> [cleanup\_on\_fail](#input\_cleanup\_on\_fail) | Deletes resources created during a failed upgrade (helm --cleanup-on-fail). | `bool` | `true` | no |
| <a name="input_cloud"></a> [cloud](#input\_cloud) | Cloud the cluster runs on: aws or azure. Sets the CNI defaults that differ per cloud. | `string` | `"aws"` | no |
| <a name="input_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#input\_cluster\_ca\_certificate) | Base64 encoded cluster CA certificate, for the node poll. | `string` | `""` | no |
| <a name="input_cluster_endpoint"></a> [cluster\_endpoint](#input\_cluster\_endpoint) | API server URL, for the node poll. Set it together with cluster\_ca\_certificate and kube\_exec to poll without a cloud CLI. | `string` | `""` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the EKS cluster, for the node poll's AWS CLI fallback. Required when wait\_for\_nodes is true and kube\_exec is not set. | `string` | `""` | no |
| <a name="input_cni"></a> [cni](#input\_cni) | CNI to install: cilium, kube-ovn (v1 chart), kube-ovn-v2 or custom. custom installs the chart in custom\_chart. | `string` | `"cilium"` | no |
| <a name="input_create"></a> [create](#input\_create) | Installs the CNI Helm release. Set false to create nothing. | `bool` | `true` | no |
| <a name="input_custom_chart"></a> [custom\_chart](#input\_custom\_chart) | Chart to install when cni = custom. release\_name defaults to the chart name; changing it later replaces the release. | <pre>object({<br/>    repository   = string<br/>    chart        = string<br/>    version      = string<br/>    release_name = optional(string)<br/>  })</pre> | `null` | no |
| <a name="input_helm_set"></a> [helm\_set](#input\_helm\_set) | Extra Helm --set values, applied after the module defaults. | `list(object({ name = string, value = string }))` | `[]` | no |
| <a name="input_helm_values"></a> [helm\_values](#input\_helm\_values) | Extra Helm values documents, applied after the module defaults. | `list(string)` | `[]` | no |
| <a name="input_k8s_service_host"></a> [k8s\_service\_host](#input\_k8s\_service\_host) | API server host without scheme, for Cilium kube-proxy replacement. Ignored unless cni = cilium and kube\_proxy\_replacement is true. | `string` | `""` | no |
| <a name="input_kube_exec"></a> [kube\_exec](#input\_kube\_exec) | Exec credential plugin the node poll authenticates with. Same shape as the helm provider's kubernetes.exec. | <pre>object({<br/>    api_version = string<br/>    command     = string<br/>    args        = optional(list(string), [])<br/>    env         = optional(map(string), {})<br/>  })</pre> | `null` | no |
| <a name="input_kube_proxy_replacement"></a> [kube\_proxy\_replacement](#input\_kube\_proxy\_replacement) | Turns on Cilium kube-proxy replacement. null means true on aws and false on azure, where kube-proxy stays on. When true, k8s\_service\_host sets k8sServiceHost and k8sServicePort. | `bool` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace of the Helm release. | `string` | `"kube-system"` | no |
| <a name="input_pod_cidr"></a> [pod\_cidr](#input\_pod\_cidr) | Pod CIDR the CNI allocates from. Required on azure, where AKS routes to it; leave empty on aws. | `string` | `""` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region of the cluster, for the node poll's AWS CLI fallback. Required when wait\_for\_nodes is true and kube\_exec is not set. | `string` | `""` | no |
| <a name="input_replace"></a> [replace](#input\_replace) | Reuses the name of a failed or pending release (helm install --replace). Set true for one apply to repair a stuck release, then set it back. | `bool` | `false` | no |
| <a name="input_service_cidr"></a> [service\_cidr](#input\_service\_cidr) | Service CIDR of the cluster, passed to the kube-ovn charts. Required for kube-ovn and kube-ovn-v2. | `string` | `""` | no |
| <a name="input_wait_for_nodes"></a> [wait\_for\_nodes](#input\_wait\_for\_nodes) | Waits for nodes to register before the install. null means true for kube-ovn and kube-ovn-v2, false otherwise. | `bool` | `null` | no |
| <a name="input_wait_for_nodes_count"></a> [wait\_for\_nodes\_count](#input\_wait\_for\_nodes\_count) | Number of matching nodes the poll waits for. Set it to the size of your CNI node pool. | `number` | `1` | no |
| <a name="input_wait_for_nodes_selector"></a> [wait\_for\_nodes\_selector](#input\_wait\_for\_nodes\_selector) | Label the node poll waits on, and the label kube-ovn pins its control plane to. null uses the module default for the selected cni; empty waits for any node. | `string` | `null` | no |
| <a name="input_wait_for_nodes_timeout"></a> [wait\_for\_nodes\_timeout](#input\_wait\_for\_nodes\_timeout) | Seconds the node poll waits before it fails. | `number` | `600` | no |
| <a name="input_wait_timeout"></a> [wait\_timeout](#input\_wait\_timeout) | Seconds Helm waits for the release to become ready. null uses the module default for the selected cni. | `number` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace of the Helm release. |
| <a name="output_release_name"></a> [release\_name](#output\_release\_name) | Name of the Helm release, null when create = false. |
| <a name="output_resolved_set"></a> [resolved\_set](#output\_resolved\_set) | Helm --set values installed: module defaults, then helm\_set. |
| <a name="output_resolved_values"></a> [resolved\_values](#output\_resolved\_values) | Helm values documents installed: module defaults, then helm\_values. |
| <a name="output_resolved_version"></a> [resolved\_version](#output\_resolved\_version) | Chart version installed, after chart\_version and the module default. |
<!-- END_TF_DOCS -->

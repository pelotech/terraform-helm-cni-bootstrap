# Changelog

## [1.1.2](https://github.com/pelotech/terraform-helm-cni-bootstrap/compare/v1.1.1...v1.1.2) (2026-10-16)


### Chores

* **deps:** bump flake-parts from `31729ca` to `024633c` ([#15](https://github.com/pelotech/terraform-helm-cni-bootstrap/issues/15)) ([d4b3486](https://github.com/pelotech/terraform-helm-cni-bootstrap/commit/d4b3486ee164f575cef068eb0618dc1a7ed4a2b5))
* **deps:** bump nixpkgs from `e158d9e` to `151fa4e` ([#16](https://github.com/pelotech/terraform-helm-cni-bootstrap/issues/16)) ([a82f619](https://github.com/pelotech/terraform-helm-cni-bootstrap/commit/a82f61915effec0bb77dcfc56783f5d6accd7eb7))
* **deps:** update actions/create-github-app-token digest to 64ab729 ([#12](https://github.com/pelotech/terraform-helm-cni-bootstrap/issues/12)) ([13f594e](https://github.com/pelotech/terraform-helm-cni-bootstrap/commit/13f594e18311887556709bee45bbf4ae7139c58d))
* **deps:** update cachix/install-nix-action action to v31.11.2 ([#13](https://github.com/pelotech/terraform-helm-cni-bootstrap/issues/13)) ([50dc877](https://github.com/pelotech/terraform-helm-cni-bootstrap/commit/50dc877a7a1394a946875d2340903294a63b247e))
* **deps:** update ghcr.io/kubeovn/charts/kube-ovn-v2 docker tag to v1.16.14 ([#10](https://github.com/pelotech/terraform-helm-cni-bootstrap/issues/10)) ([a15f00d](https://github.com/pelotech/terraform-helm-cni-bootstrap/commit/a15f00d2f57e919fe18a049928afd898f2ce7bbf))
* **deps:** update helm release cilium to v1.20.3 ([#17](https://github.com/pelotech/terraform-helm-cni-bootstrap/issues/17)) ([2b2b425](https://github.com/pelotech/terraform-helm-cni-bootstrap/commit/2b2b425cd88212e6f1be66e5fe59ac76e9e0ca3c))
* **deps:** update pre-commit hook zizmorcore/zizmor-pre-commit to v1.31.1 ([#14](https://github.com/pelotech/terraform-helm-cni-bootstrap/issues/14)) ([c29cf25](https://github.com/pelotech/terraform-helm-cni-bootstrap/commit/c29cf2566991376456be17839cf1f407e3fe4119))
* publish each release as an OpenTofu module package on ghcr.io ([#18](https://github.com/pelotech/terraform-helm-cni-bootstrap/issues/18)) ([40fa0af](https://github.com/pelotech/terraform-helm-cni-bootstrap/commit/40fa0afd23075c597e3c47ccdb473470d50b0a34))

## [1.1.1](https://github.com/pelotech/terraform-helm-cni-bootstrap/compare/v1.1.0...v1.1.1) (2026-10-08)


### Bug Fixes

* record the node poll's endpoint and credential kind instead of its kubeconfig ([#8](https://github.com/pelotech/terraform-helm-cni-bootstrap/issues/8)) ([b200078](https://github.com/pelotech/terraform-helm-cni-bootstrap/commit/b200078c6372fe2f78ca4d8b499f62e2ae42de28))

## [1.1.0](https://github.com/pelotech/terraform-helm-cni-bootstrap/compare/v1.0.0...v1.1.0) (2026-10-08)


### Features

* accept a client certificate and RKE2 defaults for the node poll ([#6](https://github.com/pelotech/terraform-helm-cni-bootstrap/issues/6)) ([a02a5ad](https://github.com/pelotech/terraform-helm-cni-bootstrap/commit/a02a5ad297b5246e8657ad93632b95817501a9fa))


### Chores

* **deps:** bump nixpkgs from `e554fab` to `e158d9e` ([#5](https://github.com/pelotech/terraform-helm-cni-bootstrap/issues/5)) ([72f2a62](https://github.com/pelotech/terraform-helm-cni-bootstrap/commit/72f2a629e60f814116c564d58b6270f955837f8c))

## 1.0.0 (2026-10-03)


### Features

* import cni-bootstrap from terraform-foundation-aws-stack ([118be5f](https://github.com/pelotech/terraform-helm-cni-bootstrap/commit/118be5f0c6276a3fc2fdb958b3be31bd6a803b89))
* poll with a rendered kubeconfig and add Azure CNI defaults ([899291a](https://github.com/pelotech/terraform-helm-cni-bootstrap/commit/899291a6a890174aed7b7b48c94cbf82724c944c))


### Chores

* **deps:** update ghcr.io/kubeovn/charts/kube-ovn-v2 docker tag to v1.16.10 ([070fe99](https://github.com/pelotech/terraform-helm-cni-bootstrap/commit/070fe993d993c9eb449f8f3956254a38a079ebab))
* **deps:** update ghcr.io/kubeovn/charts/kube-ovn-v2 docker tag to v1.16.10 ([3298b7f](https://github.com/pelotech/terraform-helm-cni-bootstrap/commit/3298b7f415c6afbdef5ed381763b0a1e03074757))
* **deps:** update pre-commit hook antonbabenko/pre-commit-terraform to v1.109.2 ([#3](https://github.com/pelotech/terraform-helm-cni-bootstrap/issues/3)) ([864fb2d](https://github.com/pelotech/terraform-helm-cni-bootstrap/commit/864fb2d0704a6b8421c957d2bfa8b58a31a7be48))

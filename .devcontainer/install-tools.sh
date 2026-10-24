#!/usr/bin/env bash
# Installs the pinned CLI toolchain (versions in tools.env) for amd64 and
# arm64 Linux. Runs once at container creation; safe to re-run.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$here/tools.env"

BIN=/usr/local/bin
case "$(uname -m)" in
  x86_64) ARCH=amd64 ;;
  aarch64 | arm64) ARCH=arm64 ;;
  *) echo "unsupported arch $(uname -m)" >&2; exit 1 ;;
esac
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }
bin_from_url() { fetch "$1" "$tmp/$2" && sudo install -m 0755 "$tmp/$2" "$BIN/$2"; }
bin_from_tgz() { # url, path-inside-archive, name
  fetch "$1" "$tmp/a.tgz" && tar -xzf "$tmp/a.tgz" -C "$tmp" && sudo install -m 0755 "$tmp/$2" "$BIN/$3"
}
bin_from_zip() { # url, name
  fetch "$1" "$tmp/a.zip" && unzip -o -q "$tmp/a.zip" -d "$tmp" && sudo install -m 0755 "$tmp/$2" "$BIN/$2"
}
hashicorp() { bin_from_zip "https://releases.hashicorp.com/$1/$2/${1}_${2}_linux_${ARCH}.zip" "$1"; }

echo "==> apt packages"
sudo apt-get update -qq
sudo apt-get install -y -qq shellcheck jq unzip bash-completion dnsutils iproute2 nftables \
  netcat-openbsd tcpdump bpftrace postgresql-client >/dev/null

echo "==> Kubernetes tooling"
bin_from_url "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" kubectl
bin_from_tgz "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz" "linux-${ARCH}/helm" helm
bin_from_url "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-${ARCH}" kind
bin_from_url "https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/k3d-linux-${ARCH}" k3d
bin_from_tgz "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${ARCH}.tar.gz" k9s k9s
bin_from_tgz "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-${ARCH}.tar.gz" kubeconform kubeconform
bin_from_url "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-${ARCH}" argocd
bin_from_tgz "https://github.com/velero-io/velero/releases/download/${VELERO_VERSION}/velero-${VELERO_VERSION}-linux-${ARCH}.tar.gz" \
  "velero-${VELERO_VERSION}-linux-${ARCH}/velero" velero

echo "==> IaC tooling"
hashicorp terraform "$TERRAFORM_VERSION"
hashicorp packer "$PACKER_VERSION"
hashicorp vault "$VAULT_VERSION"
hashicorp consul "$CONSUL_VERSION"
bin_from_zip "https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/tflint_linux_${ARCH}.zip" tflint
bin_from_tgz "https://github.com/infracost/infracost/releases/download/${INFRACOST_VERSION}/infracost-linux-${ARCH}.tar.gz" \
  "infracost-linux-${ARCH}" infracost
conftest_arch=$([[ $ARCH == amd64 ]] && echo x86_64 || echo arm64)
bin_from_tgz "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_Linux_${conftest_arch}.tar.gz" conftest conftest
pulumi_arch=$([[ $ARCH == amd64 ]] && echo x64 || echo arm64)
fetch "https://get.pulumi.com/releases/sdk/pulumi-${PULUMI_VERSION}-linux-${pulumi_arch}.tar.gz" "$tmp/pulumi.tgz"
tar -xzf "$tmp/pulumi.tgz" -C "$tmp" && sudo install -m 0755 "$tmp"/pulumi/* "$BIN/"

echo "==> Security & supply chain"
trivy_arch=$([[ $ARCH == amd64 ]] && echo 64bit || echo ARM64)
bin_from_tgz "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${trivy_arch}.tar.gz" trivy trivy
bin_from_url "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-${ARCH}" cosign
bin_from_tgz "https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}/syft_${SYFT_VERSION}_linux_${ARCH}.tar.gz" syft syft
bin_from_url "https://github.com/gruntwork-io/cloud-nuke/releases/download/${CLOUD_NUKE_VERSION}/cloud-nuke_linux_${ARCH}" cloud-nuke

echo "==> Task runner"
bin_from_tgz "https://github.com/go-task/task/releases/download/${TASK_VERSION}/task_linux_${ARCH}.tar.gz" task task

echo "==> Google Cloud CLI (apt repo)"
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor --yes -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" |
  sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
sudo apt-get update -qq && sudo apt-get install -y -qq google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin >/dev/null

echo "==> Python tooling"
pip install --quiet --user -r "$here/../requirements-dev.txt"
pre-commit install --install-hooks || true

echo "Toolchain ready. Run 'task --list' to see what you can do."

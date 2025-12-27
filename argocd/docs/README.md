# ArgoCD Debugging & Fixes

## Issue: Sync Failed for `online-boutique-prod`

**Symptom:**
The application `online-boutique-prod` was in a `Sync Failed` state with the error:
> resource networking.istio.io:Sidecar is not permitted in project online-boutique-project

**Root Cause:**
The ArgoCD `AppProject` resource (`online-boutique-project`) enforces a whitelist of allowed Kubernetes resources. The `Sidecar` resource (from Istio) was enabled in the Helm chart (`values-prod.yaml` had `sidecars: create: true`) but was missing from the allowed list in `projects.yaml`.

## The Fix

1.  **Modify `projects.yaml`:**
    Added `Sidecar` to the `namespaceResourceWhitelist` for the `networking.istio.io` group.

    ```yaml
    # infra-repo/argocd/projects/projects.yaml
    - group: networking.istio.io
      kind: Gateway
    - group: networking.istio.io
      kind: Sidecar  # <-- Added this
    ```

2.  **Apply Changes:**
    Applied the updated project configuration to the cluster:
    ```bash
    kubectl apply -f infra-repo/argocd/projects/projects.yaml
    ```

3.  **Sync Application:**
    Manually triggered a sync to verify the fix:
    ```bash
    argocd app sync online-boutique-prod --core
    ```

## Useful ArgoCD Commands

Here are the commands used during the debugging process.
*Note: Ensure `KUBECONFIG` is set correctly before running these.*

### Setup
```bash
export KUBECONFIG=~/.kube/config-external.yaml
# Set default namespace to avoid passing --namespace argocd every time
kubectl config set-context --current --namespace=argocd
```

### Debugging
*   **List Applications:**
    ```bash
    argocd app list --core
    ```
*   **Get Application Details:**
    ```bash
    argocd app get online-boutique-prod --core
    ```
*   **Sync Application:**
    ```bash
    argocd app sync online-boutique-prod --core
    ```
*   **Check Application History:**
    ```bash
    argocd app history online-boutique-prod --core
    ```
*   **Check Project Configuration:**
    ```bash
    kubectl get appproject online-boutique-project -o yaml
    ```

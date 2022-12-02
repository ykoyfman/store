---
imports:
    - kubernetes/kubectl
    - kubernetes/choose/ns
---

# Select an Active Ray Cluster Running in Kubernetes

Select a Ray cluster from the following list of active clusters in
your current Kubernetes context.

```shell
export FORCE=" "
```

=== "expand([ -z ${KUBE_CONTEXT} ] && exit 1 || kubectl get ${FORCE} ${KUBE_CONTEXT_ARG} ${KUBE_NS_ARG} pod -l type=ray -l ray-node-type=head --no-headers -o custom-columns=CLUSTER:.metadata.labels.ray-cluster-name, Ray clusters, RAY_KUBE_CLUSTER_NAME)"
    ```shell
    export RAY_KUBE_CLUSTER_NAME=${choice}
    ```

=== "Nevermind, apparently I do not have any active Ray clusters"
    No Ray clusters were found.
    ```shell
    # Indicate an early exit to madwizard
    exit 90
    ```
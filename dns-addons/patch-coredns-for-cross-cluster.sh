#!/bin/bash
set -euo pipefail

CLUSTERS=(kind-region-1 kind-region-2 kind-region-3)

# Get Docker bridge IP (host IP for kind containers)
HOST_IP=$(ip -4 addr show docker0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
if [ -z "$HOST_IP" ]; then
    echo "Failed to detect host IP from docker0"
    exit 1
fi

echo "[INFO] Detected host IP: $HOST_IP"

# Services to resolve across clusters
SERVICE_DOMAINS="service-a.local service-b.local service-c.local"

for CLUSTER in "${CLUSTERS[@]}"; do
    echo "[INFO] Patching CoreDNS in cluster: $CLUSTER"

    # Extract Corefile
    COREFILE=$(kubectl --context="$CLUSTER" -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')

    if echo "$COREFILE" | grep -q "$SERVICE_DOMAINS"; then
        echo "[WARN] CoreDNS in $CLUSTER already patched, skipping."
        continue
    fi

    # Patch with `awk` to inject the hosts block right after ".:53 {"
    PATCHED_COREFILE=$(echo "$COREFILE" | awk -v hostip="$HOST_IP" -v services="$SERVICE_DOMAINS" '
        {
            print
            if ($1 == ".:53" && $2 == "{") {
                print "    hosts {"
                print "        " hostip " " services
                print "        fallthrough"
                print "    }"
            }
        }')

    # Save to temp file
    TMPFILE=$(mktemp)
    echo "$PATCHED_COREFILE" > "$TMPFILE"

    # Apply patched Corefile
    kubectl --context="$CLUSTER" -n kube-system create configmap coredns --from-file=Corefile="$TMPFILE" --dry-run=client -o yaml | kubectl --context="$CLUSTER" -n kube-system apply -f -

    # Restart CoreDNS to apply changes
    kubectl --context="$CLUSTER" -n kube-system rollout restart deployment coredns

    echo "[DONE] CoreDNS patched in $CLUSTER"
done

echo "[SUCCESS] All clusters updated."



# Original CoreDNS ConfigMap :
#kind-region-3 ~ took 18s
#❯ k get cm coredns  -n kube-system -oyaml | yq
#apiVersion: v1
#data:
#  Corefile: |
#    .:53 {
#        errors
#        health {
#           lameduck 5s
#        }
#        ready
#        kubernetes cluster.local in-addr.arpa ip6.arpa {
#           pods insecure
#           fallthrough in-addr.arpa ip6.arpa
#           ttl 30
#        }
#        prometheus :9153
#        forward . /etc/resolv.conf {
#           max_concurrent 1000
#        }
#        cache 30 {
#           disable success cluster.local
#           disable denial cluster.local
#        }
#        loop
#        reload
#        loadbalance
#    }
#kind: ConfigMap
#metadata:
#  creationTimestamp: "2025-07-11T07:06:01Z"
#  name: coredns
#  namespace: kube-system
#  resourceVersion: "228"
#  uid: 091518e2-2021-4a38-98f8-780ac92a927e
#
#kind-region-3 ~
#❯ k get cm coredns  -n kube-system ^Coyaml | yq
#
#kind-region-3 ~
#❯ k get cm coredns  -n kube-system  --context kind-region-1 -oyaml | yq
#apiVersion: v1
#data:
#  Corefile: |
#    .:53 {
#        errors
#        health {
#           lameduck 5s
#        }
#        ready
#        kubernetes cluster.local in-addr.arpa ip6.arpa {
#           pods insecure
#           fallthrough in-addr.arpa ip6.arpa
#           ttl 30
#        }
#        prometheus :9153
#        forward . /etc/resolv.conf {
#           max_concurrent 1000
#        }
#        cache 30 {
#           disable success cluster.local
#           disable denial cluster.local
#        }
#        loop
#        reload
#        loadbalance
#    }
#kind: ConfigMap
#metadata:
#  creationTimestamp: "2025-07-11T07:05:13Z"
#  name: coredns
#  namespace: kube-system
#  resourceVersion: "265"
#  uid: ce1e00d4-d512-44ce-bec2-919e2fa69e66
#
#kind-region-3 ~
#❯ k get cm coredns  -n kube-system  --context kind-region-2 -oyaml | yq
#apiVersion: v1
#data:
#  Corefile: |
#    .:53 {
#        errors
#        health {
#           lameduck 5s
#        }
#        ready
#        kubernetes cluster.local in-addr.arpa ip6.arpa {
#           pods insecure
#           fallthrough in-addr.arpa ip6.arpa
#           ttl 30
#        }
#        prometheus :9153
#        forward . /etc/resolv.conf {
#           max_concurrent 1000
#        }
#        cache 30 {
#           disable success cluster.local
#           disable denial cluster.local
#        }
#        loop
#        reload
#        loadbalance
#    }
#kind: ConfigMap
#metadata:
#  creationTimestamp: "2025-07-11T07:05:35Z"
#  name: coredns
#  namespace: kube-system
#  resourceVersion: "275"
#  uid: 2f1f14b3-0470-4072-8004-2c1101db210c
#
#kind-region-3 ~
#❯ k get cm coredns  -n kube-system  --context kind-region-3 -oyaml | yq
#apiVersion: v1
#data:
#  Corefile: |
#    .:53 {
#        errors
#        health {
#           lameduck 5s
#        }
#        ready
#        kubernetes cluster.local in-addr.arpa ip6.arpa {
#           pods insecure
#           fallthrough in-addr.arpa ip6.arpa
#           ttl 30
#        }
#        prometheus :9153
#        forward . /etc/resolv.conf {
#           max_concurrent 1000
#        }
#        cache 30 {
#           disable success cluster.local
#           disable denial cluster.local
#        }
#        loop
#        reload
#        loadbalance
#    }
#kind: ConfigMap
#metadata:
#  creationTimestamp: "2025-07-11T07:06:01Z"
#  name: coredns
#  namespace: kube-system
#  resourceVersion: "228"
#  uid: 091518e2-2021-4a38-98f8-780ac92a927e
#
#kind-region-3 ~
#❯

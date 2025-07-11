#!/bin/bash



clusters=("kind-region-1" "kind-region-2" "kind-region-3")
names=("a" "b" "c")

for i in "${!clusters[@]}"; do
    cluster="${clusters[$i]}"
    name="${names[$i]}"
    cat <<EOF | kubectl apply --context "$cluster" -f -
apiVersion: v1
kind: Pod
metadata:
  name: service-${name}-app
  labels:
    app: service-${name}
spec:
  containers:
    - name: service-${name}-app
      image: registry.k8s.io/e2e-test-images/agnhost:2.39
      command: ["/agnhost", "serve-hostname", "--http=true", "--port=8080"]
---
apiVersion: v1
kind: Service
metadata:
  name: service-${name}-service
spec:
  selector:
    app: service-${name}
  ports:
    - port: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: service-${name}-ingress
spec:
  rules:
    - host: service-${name}.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: service-${name}-service
                port:
                  number: 8080
EOF
done
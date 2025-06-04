#!/bin/bash

kubectl apply -f k8s-deployment/service-a/deployment.yaml --context kind-region-a1
kubectl apply -f k8s-deployment/service-b/deployment.yaml --context kind-region-b1
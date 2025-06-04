#!/bin/bash

k apply -f nginx-ingress-controller/deploy-ingress-nginx.yaml --context kind-region-a1
k apply -f nginx-ingress-controller/deploy-ingress-nginx.yaml --context kind-region-b1
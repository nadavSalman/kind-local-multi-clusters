#!/bin/bash

kind create cluster --name region-a1 --config kind-clusters-conf/region-a1.yaml
kind create cluster --name region-b1 --config kind-clusters-conf/region-b1.yaml
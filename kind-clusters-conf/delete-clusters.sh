❯ kind delete clusters region-a1
Deleted nodes: ["region-a1-control-plane" "region-a1-worker" "region-a1-worker2" "region-a1-worker3"]
Deleted clusters: ["region-a1"]

on kind-region-b1 kind-local-multi-clusters on  main [!] took 2s 
❯ kind delete clusters region-b1
Deleted nodes: ["region-b1-control-plane" "region-b1-worker2" "region-b1-worker" "region-b1-worker3"]
Deleted clusters: ["region-b1"]




```mermaid
graph LR
  client["Client Request"]-.->|Request to service-a.local| nginx_proxy
  client-.->|Request to service-b.local| nginx_proxy

  subgraph Host_Machine["Host Machine"]
    direction TB
    etc_hosts["/etc/hosts<br>127.0.0.1 service-a.local<br>127.0.0.1 service-b.local"]
    nginx_proxy["NGINX Reverse Proxy<br><i>(Listens on ports 80 & 443)</i>"]
  end

  subgraph Cluster_A["Cluster A"]
    direction TB
    ingress_a["NGINX Ingress Controller<br><i>(Listens on 80 & 443)</i><br>hostPort: 8081 → 80<br>hostPort: 8444 → 443"]
    service_a["Service A"]
  end

  subgraph Cluster_B["Cluster B"]
    direction TB
    ingress_b["NGINX Ingress Controller<br><i>(Listens on 80 & 443)</i><br>hostPort: 8082 → 80<br>hostPort: 8445 → 443"]
    service_b["Service B"]
  end

  nginx_proxy -->|Forward to port 8081| ingress_a
  nginx_proxy -->|Forward to port 8082| ingress_b

  ingress_a --> service_a
  ingress_b --> service_b

  %% Classes & styling like Kubernetes ODC theme
  classDef plain fill:#ddd,stroke:#fff,stroke-width:4px,color:#000,font-family:Arial;
  classDef k8s fill:#326ce5,stroke:#fff,stroke-width:4px,color:#fff,font-family:Arial;
  classDef cluster fill:#fff,stroke:#bbb,stroke-width:2px,color:#326ce5,font-family:Arial;

  class client plain;
  class nginx_proxy k8s;
  class ingress_a,ingress_b,service_a,service_b k8s;
  class Host_Machine,Cluster_A,Cluster_B cluster;
  class etc_hosts plain;


```


NGINX Reverse Prox Logic :

```bash
server {
    listen 80;
    server_name service-a.local;
    location / {
        proxy_pass http://localhost:8081;
    }
}

server {
    listen 80;
    server_name service-b.local;
    location / {
        proxy_pass http://localhost:8082;
    }
}
```








```mermaid
graph TD
    subgraph Host_Machine
        direction TB
        etc_hosts["<pre>/etc/hosts<br>127.0.0.1 service-a.local<br>127.0.0.1 service-b.local</pre>"]
        nginx_proxy["NGINX Reverse Proxy<br><i>(Listens on ports 80 & 443)</i>"]
    end

    subgraph Cluster_A
        direction TB
        ingress_a["NGINX Ingress Controller<br><i>(Listens on 80 & 443)</i><br>hostPort: 8081 → 80<br>hostPort: 8444 → 443"]
        service_a["Service A"]
    end

    subgraph Cluster_B
        direction TB
        ingress_b["NGINX Ingress Controller<br><i>(Listens on 80 & 443)</i><br>hostPort: 8082 → 80<br>hostPort: 8445 → 443"]
        service_b["Service B"]
    end

    client["Client Request"]

    client -->|Request to service-a.local| nginx_proxy
    client -->|Request to service-b.local| nginx_proxy

    nginx_proxy -->|Forward to port 8081| ingress_a
    nginx_proxy -->|Forward to port 8082| ingress_b

    ingress_a --> service_a
    ingress_b --> service_b
```


NGINX Reverse Prox Logic :

```json
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




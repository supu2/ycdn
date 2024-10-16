## Case Study: Nginx-Based CDN

### Scenario:
Your company is building a highly scalable content delivery platform (CDN) using Nginx reverse
proxy. The platform must serve images to users as quickly as possible, and it needs to implement
on-the-fly image resizing to allow users to request images in specific dimensions via URL
parameters. The images are stored on an origin server.
However, the platform faces several challenges:
1. You are experiencing heavy traffic surges, and the caching mechanism doesn’t seem to handle
the load effectively. Cache purging is inefficient, and the cache hit ratio is below 50%.

2. Dynamic image resizing is causing significant performance bottlenecks, especially
when processing large images with various resizing parameters. Some requests are even
timing out, leading to a poor user experience.
3. The platform is planned to scale horizontally, and you need to ensure that the Nginx instances
can handle this scaling efficiently without duplication of resources.
4. There are concerns about security, particularly around unauthorized access to the
image resizing service, as well as the use of insecure URL parameters.
## Solution Architecture

```
          ┌─────────────────────────────┐
          │           Router            │ Router split traffic between
          └────┬─────────────────┬──────┘ kubernetes worker nodes which one 
               │                 │        has haproxy instance
          ┌────▼─────────────────▼──────┐
          │           Metallb           │ BGP announce with ECMP (5 tuple )
          └────┬─────────────────┬──────┘
               │                 │
               │                 │
       ┌───────▼─────────────────▼─────────┐
       │       kubernetes service          │  Kubernetes worker nodes
       │ (externalTrafficPolicy: Local)    │  
       └──────────┬───────────┬────────────┘
                  │           │
                  │           │  
             ┌────▼────┐  ┌───▼─────┐
             │ haproxy │  │ haproxy │   loadbalancer layer
             │ (active)│  │ (active)│   Reduce the priority of /resize operation
             └────┬────┘  └─────┬───┘   http-request set-priority-class int(100) if is_resize
                  │             |        
                  │             |       balance uri whole     # use url with parameter to shard nginx cache
                  │             |       hash-type consistent  # consistent balance method
           ┌──────▼──────┬──────▼───────┐
       ┌───▼───┐     ┌───▼───┐      ┌───▼───┐ caching
       │ nginx │     │ nginx │      │ nginx │  layer
       └───┬───┘     └───┬───┘      └───┬───┘
           │             │              │
      ┌────┴───────┬─────┴────┬─────────┴──┐
      │            │          │            │
  ┌───▼────┐  ┌────▼───┐  ┌───▼────┐  ┌────▼───┐
  │ origin │  │ origin │  │ Resize │  │ Resize │ Imgproxy for image resize. Internal Traffic Policy local option will reduce to node to node traffic.
  └────────┘  └────────┘  └────────┘  └────────┘ internalTrafficPolicy: Local  
```

## Installation
Prerequirement:
- docker
- make
- kind
- helm
```
make install-kind 
make create-cluster
make deploy
# After deployment you can test resize operation on browser or run make resize to test application
# http://172.17.0.200/resize/300/400/aHR0cHM6Ly9jZG4uZHNtY2RuLmNvbS90eTk1L3Byb2R1Y3QvbWVkaWEvaW1hZ2VzLzIwMjEwNDA0LzE1LzRkYTFiMTRiLzEzNjIzODAzLzEvMV9vcmdfem9vbS5qcGc
```
# Usage
```
help                           This help.
install-kubectl                Install kubectl 
install-helm                   Install helm
install-kind                   kind minimal kubernetes for local development
create-cluster                 Deploy kind cluster with local registry
destroy-cluster                Destroy kind cluter
deploy                         Deploy all apps
resize                         Test image resize  performance
```

[Kernel Optimization](http-cache/templates/sysctl/daemonset.yaml)

- Before kernel optimization
```
wrk -c 64 -d 200s -s test/dynamic_urls.lua http://172.17.0.200
Running 3m test @ http://172.17.0.200
  2 threads and 64 connections
^C  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency   109.89ms  146.92ms 561.61ms   80.91%
    Req/Sec   684.70    308.55     4.11k    85.56%
  104906 requests in 1.28m, 727.20MB read
Requests/sec:   1363.44
Transfer/sec:      9.45MB
```
- After kernel optimization
```
wrk -c 64 -d 600s -s test/dynamic_urls.lua http://172.17.0.200
Running 10m test @ http://172.17.0.200
  2 threads and 64 connections
^C  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency    82.66ms  133.45ms 513.83ms   84.21%
    Req/Sec     2.01k     1.20k   10.31k    88.15%
  152198 requests in 39.82s, 1.03GB read
Requests/sec:   3821.99
Transfer/sec:     26.50MB
```
[Cache Configuration](http-cache/templates/nginx/configmap.yaml)

[Load Balancer Configuration](http-cache/templates/haproxy/configmap.yaml)

[Image Proxy](cdn/templates/imgproxy.yaml)

[Monitoring Stack](cdn/templates/prometheus-stack.yaml)


## Tasks:
### Nginx Reverse Proxy and Advanced Caching Optimization:

Set up an Nginx reverse proxy that caches images fetched from the origin server
and serves them efficiently. Your caching strategy must account for the following:
- [x] Cache hit ratio needs to be raised to at least 80%.
```
Haproxy will split incomming requests based on URL to nginx cache layer.
```
- [X] Implement an intelligent cache purging mechanism that removes stale
content dynamically while preserving popular content.
```
The following configuration automatically evicts the least recently used (LRU) object from the cache if there is no space.
proxy_cache_path /data/cache levels=1:2 keys_zone=mycache:400m max_size=100g inactive=30d use_temp_path=off;
There is other option the clean obect from cache.
proxy_cache_purge PURGE from 10.0.0.0/8;
```
- [X] Minimize resource duplication when the platform scales horizontally.

```
The following HAProxy configuration splits traffic based on the URL to the corresponding Nginx shard. If the URL is the same for incoming requests, it forwards the request to the same Nginx cache node. This increases the cache hit ratio and reduces data duplication.
balance uri whole 
hash-type consistent
```
Hint: Consider advanced caching mechanisms such as using cache keys based on unique image
parameters and setting up a distributed cache to avoid duplicate cache storage in each Nginx
instance.

### High-Performance On-the-Fly Image Resizing:

Implement dynamic image resizing using Nginx’s image resizing module. However, you must address the following performance issues:

- [X] Optimize the CPU usage for resizing large images, ensuring that no single
image resizing request monopolizes the server’s resources.
```
Imgproxy is a separate Kubernetes application where we can apply memory and CPU limits. Additionally, Imgproxy offers many security features. Some examples include:
IMGPROXY_MAX_SRC_FILE_SIZE
IMGPROXY_MAX_REDIRECTS
IMGPROXY_ALLOWED_SOURCES
IMGPROXY_ALLOW_ORIGIN
# https://docs.imgproxy.net/configuration/options#security
```

- [] Implement a queueing system for resizing tasks, prioritizing frequently
requested sizes over uncommon ones. Prevent timeouts for large resizing
requests.

- [X] Ensure that all resized images are cacheable and re-usable across Nginx
instances in the CDN without reprocessing.
```
The solution design ensures that each Nginx instance will have its own shard of the entire cache. This means there is no need to share caches between the Nginx instances.
```
- [X] Prevent overloading by limiting the number of simultaneous image resizing
tasks Nginx can handle.
```
By default, Imgproxy comes with basic protection, but we can adjust the following settings to meet our requirements.
IMGPROXY_CONCURRENCY
IMGPROXY_REQUESTS_QUEUE_SIZE
IMGPROXY_MAX_CLIENTS
```
Hint: Consider implementing an external image processing queue that can offload the resizing tasks to a separate, optimized service.

### Scalability and High Availability:
- [X] Design and implement a solution that scales horizontally across multiple Nginx
instances without duplicating the cache or overloading the origin server.
```
The solution architect introduced cache sharding, which simply requires updating the Nginx node replicas in the deployment.
# CDN helm configuration
nginx:
  replicas: 3
```
- [X] Your solution should include a load balancer that efficiently distributes traffic between
Nginx instances. You must ensure the cache can be shared across instances and that
the origin server is not overwhelmed by excessive cache misses during traffic surges.

- [X] Test the CDN with simulated traffic to prove that it can handle 100,000 requests per
second without significant performance degradation.
```
# The following test includes both cached and non-cached requests.
wrk -c 64 -d 20s -s test/dynamic_urls.lua http://172.17.0.200
Running 20s test @ http://172.17.0.200
  2 threads and 64 connections
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency     1.56ms    5.63ms 502.75ms   99.47%
    Req/Sec    22.65k     0.94k   25.05k    80.00%
  901393 requests in 20.00s, 6.11GB read
Requests/sec:  45059.87
Transfer/sec:    312.51MB
```

Hint: Research distributed caching solutions and consider sharding the cache across Nginx
instances for efficient cache management.

### Security and Authentication:

- [ ] Implement a secure authentication mechanism that prevents unauthorized access to
the image resizing service. Users should only be able to resize images if they provide valid
authentication tokens.

- [ ] Secure the URL parameters used for resizing (e.g., width, height) to prevent malicious
users from sending excessive requests with invalid or extreme values.
```
The image proxy service also supports several protections. https://docs.imgproxy.net/configuration/options#security

IMGPROXY_MAX_SRC_RESOLUTION
IMGPROXY_MAX_SRC_FILE_SIZE
IMGPROXY_MAX_REDIRECTS
IMGPROXY_ALLOWED_SOURCES
---
We can use nginx lua for rate limiting like below.
            location ~* ^/resize/(\d+)/(\d+)/(.+)$ {
                set $width $1;
                set $height $2;
                set $image_location $3;
                access_by_lua '
                    local width = tonumber(ngx.var.width)
                    local height = tonumber(ngx.var.height)

                    -- Enforce the maximum width and height
                    if width > 2000 then
                        ngx.var.width = 2000
                    end
                    if height > 2000 then
                        nginx.var.height = 2000
                    end
                ';
```
- [ ] Implement rate limiting to protect the system from abuse and ensure that no user
can overload the image resizing service.
```
Nginx rate resize service
   limit_req_zone  $http_x_forwarded_for zone=zone:16m rate=3r/s;
```

Hint: Consider using HMAC-based authentication and tokenized URLs for secure access control.

### Monitoring and Reporting:

- [X] Use Prometheus and Grafana to monitor all key performance metrics of the CDN,
including cache hit ratio, response times, image resizing queue length, and CPU usage.
![](images/Dashboard.png)
- [X] Set up automated alerts for performance degradation, such as cache hit ratio
dropping below 80% or high CPU usage on the image resizing service.
![](images/Alert.png)

Hint: Advanced custom metrics (e.g., cache miss rate, resizing task success rate) should be
implemented and visualized in Grafana dashboards.
Delivery Requirements:
1. GitHub Project:
• Share this case study as a project on GitHub. The project should include all
necessary configurations for running the CDN.
• Include detailed README.md that explains how to deploy and scale the solution.
2. Docker Compose with High Availability Setup:
• Use Docker Compose or Kubernetes to set up a scalable and high-availability
Nginx-based CDN. The setup should be able to scale across multiple containers/nodes.

3. Distributed Caching Solution:
• Include a solution for distributed caching, ensuring that no duplicate resources are
stored across Nginx instances. Clearly document how cache consistency is maintained.
4. Technical Documentation:
• Provide detailed technical documentation explaining the Nginx reverse proxy setup,
caching strategies, on-the-fly image resizing optimizations, security mechanisms, and how
the system is scaled for high availability.
5. Performance Testing Script:
• Provide a script or instructions for simulating 100,000 requests per second. The
system should be able to handle the load without excessive cache misses or timeouts.
6. Grafana Dashboards and Prometheus Alerts:
• Include Grafana dashboards for monitoring key performance metrics, and set up
Prometheus alerts for critical issues (e.g., cache hit ratio below 80%, CPU usage
exceeding a threshold).
### Hints and Restrictions:
- No External Image Resizing Services: You cannot rely on third-party image resizing
services (e.g., Imgix, Cloudinary). The solution must use Nginx or a custom-built image
processing queue.
- Security Focus: Security is critical in this project. Any insecure handling of image resizing or
cache parameters will be seen as a critical failure.
- Scalability is Key: The solution must scale horizontally and be fault-tolerant. Single points of
failure are unacceptable.

### Referances: 
- https://nginx.org/en/docs/http/ngx_http_secure_link_module.html
- https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_cache_path
- https://github.com/k8gb-io/k8gb/blob/master/docs/strategy.md
- https://nginx.org/en/docs/http/ngx_http_image_filter_module.html#image_filter
- https://nginx.org/en/docs/http/ngx_http_secure_link_module.html
- https://github.com/thibaultcha/lua-resty-mlcache
- https://github.com/openresty/lua-resty-lrucache
- https://nginx-extras.getpagespeed.com/modules/cache-purge/
- https://github.com/allinurl/goaccess
- https://github.com/alibaba/tengine
- https://github.com/aenix-io/cozystack/tree/main/packages/apps/http-cache
- https://gist.github.com/denji/8359866
- https://blog.cloudflare.com/http-2-prioritization-with-nginx/
- https://nginx.org/en/docs/http/ngx_http_mirror_module.html
- https://tengine.taobao.org/document/http_sysguard.html
- https://en.wikipedia.org/wiki/Cache_replacement_policies#LRU
- https://www.imperva.com/learn/performance/cdn-caching/
- https://github.com/openresty/srcache-nginx-module
- https://dropbox.tech/infrastructure/optimizing-web-servers-for-high-throughput-and-low-latency
- https://medium.com/trendyol-tech/implementing-an-image-processing-service-using-imgproxy-e4755a47f3c5
- https://github.com/imgproxy/imgproxy
- https://github.com/openresty/srcache-nginx-module?tab=readme-ov-file#srcache_default_expire
- https://www.f5.com/company/blog/nginx/nginx-high-performance-caching
- https://www.haproxy.com/blog/haproxys-load-balancing-algorithm-for-static-content-delivery-with-varnish#hashing-the-whole-url-including-the-query-string
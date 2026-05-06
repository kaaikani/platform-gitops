# Grafana Dashboards — Scenario-Based SRE/DevOps Guide

**Grafana URL:** `https://graf.avsecomhub.com`
**Login:** admin / VendureTest2026

All 7 custom dashboards are provisioned automatically via ConfigMaps with `grafana_dashboard=1`.
Find them in Grafana → **Dashboards → Browse → (folder: General or search by name)**.

---

## Dashboard Index

| # | Dashboard | Primary Use |
|---|-----------|-------------|
| 1 | Vendure Application | App health, API performance, business metrics |
| 2 | Kubernetes Cluster Health | Node/pod status, resource pressure |
| 3 | Loki Log Analytics | Log search, error spikes, Vendure logs |
| 4 | Tempo Tracing | Distributed traces, slow requests, latency root cause |
| 5 | SLO / SLI & Error Budget | Uptime SLO, burn rate, incident detection |
| 6 | Node & Pod Resources | Per-node CPU/mem, top consumers, OOM risk |
| 7 | Ingress & Network | Traffic flow, DNS, bandwidth, connectivity |

---

## 1. Vendure Application Dashboard

**File:** `vendure-application.json`

### What It Shows
- HTTP request rate, error rate, p50/p95/p99 latency
- Node.js event loop lag, heap memory, GC pressure
- Active HTTP connections, process uptime
- Business metrics: orders created, revenue events

### Scenarios

#### Scenario A — "API is slow, customers complaining"
1. Open **Vendure Application** dashboard
2. Check **HTTP p95 Latency** panel — is it above 500ms?
3. Check **Request Rate by Route** — which endpoint is the culprit?
4. Check **Event Loop Lag** — if >50ms, Node.js is CPU-starved
5. Check **Heap Used** — if >85% of heap limit, memory pressure causing GC pauses
6. If heap looks fine → go to **Tempo Tracing** dashboard and trace the slow endpoint

#### Scenario B — "Spike in 5xx errors"
1. Check **HTTP Error Rate** panel — when did it start?
2. Check **Errors by Status Code** — 502 = upstream crash, 503 = no pods, 504 = timeout
3. If 502/503 → go to **K8s Cluster Health** and check pod restarts
4. If 504 → likely DB slowness — check **Event Loop Lag** and DB connection pool

#### Scenario C — "Orders are not being placed"
1. Check **Orders Created Rate** panel — flat line means no orders flowing
2. Check **HTTP Error Rate** for the `/shop-api` path
3. Cross-reference with **Loki Log Analytics** → search `{app="vendure"} |= "error"` for payment/order errors

---

## 2. Kubernetes Cluster Health Dashboard

**File:** `kubernetes-cluster-health.json`

### What It Shows
- Node count, pod count, cluster CPU/memory utilization
- Pod restarts, OOMKilled events
- Resource requests vs actual usage
- Deployment and DaemonSet health
- Kubernetes API server latency

### Scenarios

#### Scenario A — "Deployment is not rolling out"
1. Open **Kubernetes Cluster Health**
2. Check **Deployment Health** table — look for `unavailableReplicas > 0`
3. Check **Pod Restart Heatmap** — which pods are restarting?
4. For OOMKilled: check **OOMKilled Events** counter + go to **Node & Pod Resources**
5. For CrashLoopBackOff: go to **Loki Log Analytics** → filter by pod name

#### Scenario B — "Cluster is running out of resources"
1. Check **Cluster CPU Usage** and **Cluster Memory Usage** — above 80%?
2. Check **Node Pressure** table — `MemoryPressure` or `DiskPressure` conditions set?
3. If a node is at >90% → check **Node & Pod Resources** for top consumers
4. If all nodes are full → Karpenter should be provisioning new nodes; check `kubectl get nodeclaims`

#### Scenario C — "kubectl is slow / API server issues"
1. Check **API Server Request Duration** panel — p99 above 1s is a problem
2. Check **API Server Request Rate** — unusually high indicates control plane pressure
3. Check **etcd** panels for leader election events

---

## 3. Loki Log Analytics Dashboard

**File:** `loki-log-analytics.json`

### What It Shows
- Log volume over time by namespace and pod
- Error/warning log rates
- Vendure-specific log patterns (order, payment, auth events)
- Loki ingestion health and query performance

### Scenarios

#### Scenario A — "Need to debug a failed payment"
1. Open **Loki Log Analytics**
2. In **Vendure Error Logs** panel, look for `payment` or `razorpay` in recent entries
3. Copy the timestamp of the error
4. Use Grafana Explore → Loki datasource:
   ```
   {namespace="vendure-test", app="vendure"} |= "payment" | json | line_format "{{.msg}}"
   ```
5. If you see `webhook` errors → check Razorpay dashboard for the payment ID

#### Scenario B — "Application logs disappeared"
1. Check **Log Ingestion Rate** panel — flat line means Promtail is not scraping
2. Check **Loki Health** panels — ingestion errors or OOM?
3. Check: `kubectl get pods -n monitoring -l app=promtail`
4. Check Promtail logs: `kubectl logs -n monitoring ds/prometheus-stack-promtail --tail=50`

#### Scenario C — "Spike in errors after a deployment"
1. Check **Error Log Rate** panel — did it spike after your deploy time?
2. Use time picker to set range to "last 30 minutes"
3. **Error Logs by Pod** panel — which pod version is erroring?
4. Check **Log Volume by Pod** — new pod name confirms the new deployment
5. If errors confirm regression → go to GitHub Actions → run **Rollback** workflow

#### How to Use Loki Explore (Ad-hoc Queries)
- Go to **Explore** → Select **Loki** datasource
- Filter by namespace: `{namespace="vendure-test"}`
- Filter by app: `{app="vendure"}`
- Search for string: `|= "error"`
- Parse JSON logs: `| json`
- Count errors: `| json | __error__="" | count_over_time([5m])`

---

## 4. Tempo Tracing Dashboard

**File:** `tempo-tracing.json`

### What It Shows
- Request traces across services
- P50/P95/P99 trace duration
- Slow span breakdown (where time is spent)
- Error traces and failed operations
- Service dependency map

### Scenarios

#### Scenario A — "Find the root cause of slow API requests"
1. Open **Tempo Tracing** dashboard
2. Check **P95 Trace Duration** — which service/operation is slow?
3. Click a slow trace to open the **Trace View**
4. Look for long spans → identify DB queries, external HTTP calls, etc.
5. Common culprits:
   - Long DB span → query needs index or N+1 issue
   - Long HTTP span → external API (Razorpay, SMS) timeout
   - Long `vendure.worker` span → job queue backlog

#### Scenario B — "Trace a specific customer order end-to-end"
1. Go to **Explore** → Select **Tempo** datasource
2. Use TraceQL query:
   ```
   {.http.route="/shop-api" && .http.method="POST" && duration > 1s}
   ```
3. Or search by order ID if you have trace correlation in logs:
   ```
   {namespace="vendure-test"} |= "ORDER-XYZ" | json | traceID != ""
   ```
4. Click the traceID link → opens full distributed trace

#### Scenario C — "How to enable tracing in Vendure"
Tempo requires OpenTelemetry instrumentation. To add tracing:
```typescript
// In src/index.ts
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({
    url: 'http://prometheus-stack-tempo.monitoring:4318/v1/traces',
  }),
});
sdk.start();
```

---

## 5. SLO / SLI & Error Budget Dashboard

**File:** `slo-sli-error-budget.json`

### What It Shows
- **Availability SLO**: 99.9% uptime target (43m budget/month)
- **Latency SLO**: 95% of requests under 500ms
- **Error Budget**: How much budget is remaining / being burned
- **Burn Rate**: Alert if burning budget too fast (1x, 5x, 14x)
- **SLO Compliance History**: Weekly/monthly view

### Scenarios

#### Scenario A — "Is our service meeting SLO this month?"
1. Open **SLO / SLI** dashboard
2. Set time range to **Last 30 days**
3. Check **Availability SLO** gauge — green (>99.9%), yellow (>99%), red (<99%)
4. Check **Error Budget Remaining** — if below 20%, be very careful with deploys
5. Check **Burn Rate (1h)** — if >14x, you have a P1 incident right now

#### Scenario B — "Incident post-mortem — how much SLO did we lose?"
1. Set time range to the incident window
2. Check **Availability SLI** panel for the exact downtime duration
3. Check **Error Budget Consumed** panel — how many minutes of budget burned?
4. Export the panel data (Panel menu → Inspect → Data → Download CSV)
5. Use this data in your post-mortem report

#### Scenario C — "Set up burn rate alerts"
The dashboard shows burn rate alerts visually. To add PagerDuty/Slack alerting:
1. Go to **Alerting** → **Alert Rules** in Grafana
2. Create rule based on this PromQL:
   ```promql
   # 1-hour burn rate > 14x (critical)
   (
     sum(rate(vendure_http_request_duration_seconds_count{status=~"5.."}[1h]))
     /
     sum(rate(vendure_http_request_duration_seconds_count[1h]))
   ) > (1 - 0.999) * 14
   ```
3. Set contact point to Slack webhook or PagerDuty integration key

---

## 6. Node & Pod Resources Dashboard

**File:** `node-pod-resources.json`

### What It Shows
- Per-node CPU usage, memory usage, disk I/O, network
- Top 10 CPU-consuming pods
- Top 10 memory-consuming pods
- Requests vs limits vs actual usage
- Pod lifecycle events (starts, stops, OOMs)

### Scenarios

#### Scenario A — "A node is at 95% CPU — which pod is causing it?"
1. Open **Node & Pod Resources**
2. Select the hot node from the **Node** dropdown
3. Check **Top CPU Consumers** table — sorted by CPU usage
4. Identify the pod → go to **Loki Log Analytics** → filter by that pod name
5. If it's the Vendure pod → check **Vendure Application** for request rate spike

#### Scenario B — "Pod got OOMKilled — what was using the memory?"
1. Check **OOM Events** counter panel — confirm it happened
2. In **Top Memory Consumers** — the pod that was killed will show max memory
3. Check **Memory Usage vs Limit** — was the limit set too low?
4. Fix: update `resources.limits.memory` in `helm/environments/test/vendure-values.yaml`
5. Redeploy and watch **Heap Used** in **Vendure Application** dashboard

#### Scenario C — "Plan a resource right-sizing exercise"
1. Set time range to **Last 7 days**
2. Check **CPU Request vs Actual Usage** panel — over-provisioned pods waste money
3. Check **Memory Request vs Actual Usage** — identify pods with >50% slack
4. Target: actual usage should be ~70% of request
5. Adjust `resources.requests` in Helm values and re-deploy via CI/CD

#### Scenario D — "Karpenter isn't scaling — is there room on existing nodes?"
1. Check **Node CPU Allocatable vs Requested** — is there unscheduled capacity?
2. Check **Node Memory Allocatable vs Requested** — same
3. If both are near 100% and new pods are Pending → check:
   ```bash
   kubectl describe node <node-name> | grep -A5 "Allocated resources"
   kubectl get events -n vendure-test --sort-by='.lastTimestamp' | tail -20
   ```

---

## 7. Ingress & Network Dashboard

**File:** `ingress-network.json`

### What It Shows
- Ingress request rate, error rate, latency by host/path
- Network bytes in/out per namespace and pod
- Node-level network throughput
- DNS resolution rates and errors
- Service endpoint connectivity

### Scenarios

#### Scenario A — "A subdomain is unreachable — is it the Ingress or upstream?"
1. Open **Ingress & Network**
2. Find your host (e.g., `test.avsecomhub.com`) in **Ingress Traffic by Host**
3. If request rate = 0 → traffic not reaching the ingress (DNS or Cloudflare issue)
4. If request rate > 0 but error rate is high → ingress is receiving but backend is failing
5. Check **Backend Connectivity** panel — is the upstream service healthy?
6. Also check:
   ```bash
   kubectl get ingress -n vendure-test
   kubectl describe ingress shared-alb-ingress -n vendure-test
   ```

#### Scenario B — "Bandwidth costs are unexpectedly high"
1. Check **Network Bytes Out by Namespace** — which namespace is egress-heavy?
2. Check **Top Pods by Network Out** — identify the specific pod
3. Common causes: excessive logging, large API responses, mis-configured scraping
4. Check **Bytes Out Rate** over time — is it a constant leak or a spike?

#### Scenario C — "DNS resolution failures causing service errors"
1. Check **DNS Query Rate** and **DNS Error Rate** panels
2. If DNS errors are high → CoreDNS might be under pressure:
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   kubectl top pods -n kube-system
   ```
3. Check for `NXDOMAIN` errors — usually a misconfigured service name in application code

---

## Quick Reference — SRE Runbook Checklist

### P1 Incident (Site Down)
```
1. SLO/SLI Dashboard     → Confirm burn rate > 14x
2. K8s Cluster Health    → Check pod restarts, node health
3. Ingress & Network     → Confirm traffic hitting ingress
4. Vendure Application   → Check error rate and HTTP status
5. Loki Log Analytics    → Get last error logs
6. Tempo Tracing         → Find failed traces (if instrumented)
```

### P2 Incident (Degraded Performance)
```
1. Vendure Application   → p95 latency > 500ms?
2. Node & Pod Resources  → CPU/memory pressure?
3. Tempo Tracing         → Which span is slow?
4. Loki Log Analytics    → Any new error patterns?
```

### Post-Deployment Verification (5-min check)
```
1. Vendure Application   → Error rate unchanged, latency unchanged
2. K8s Cluster Health    → New pods Running, no restarts
3. SLO/SLI Dashboard     → Error budget not burning
4. Loki Log Analytics    → No new error patterns in pod logs
```

### Capacity Planning (Monthly)
```
1. Node & Pod Resources  → Requests vs actual (7-day avg)
2. K8s Cluster Health    → Node utilization trend
3. Ingress & Network     → Bandwidth growth trend
4. SLO/SLI Dashboard     → Error budget consumption rate
```

---

## Datasource Configuration

| Datasource | Type | Internal URL |
|------------|------|--------------|
| Prometheus | prometheus | `http://prometheus-stack-kube-prom-prometheus:9090` |
| Loki | loki | `http://prometheus-stack-loki:3100` |
| Tempo | tempo | `http://prometheus-stack-tempo:3100` |

To verify datasources are healthy:
**Grafana → Configuration → Data Sources → Test**

---

## Useful PromQL Snippets

```promql
# Vendure request rate
rate(vendure_http_request_duration_seconds_count[5m])

# Vendure p95 latency
histogram_quantile(0.95, rate(vendure_http_request_duration_seconds_bucket[5m]))

# Vendure error rate
sum(rate(vendure_http_request_duration_seconds_count{status=~"5.."}[5m]))
/ sum(rate(vendure_http_request_duration_seconds_count[5m]))

# Pod CPU usage
sum(rate(container_cpu_usage_seconds_total{namespace="vendure-test"}[5m])) by (pod)

# Pod memory usage
sum(container_memory_working_set_bytes{namespace="vendure-test"}) by (pod)

# Error budget remaining (30d)
1 - (
  sum(increase(vendure_http_request_duration_seconds_count{status=~"5.."}[30d]))
  / sum(increase(vendure_http_request_duration_seconds_count[30d]))
) / (1 - 0.999)
```

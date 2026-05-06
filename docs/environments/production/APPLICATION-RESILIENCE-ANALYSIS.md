# Application Resilience Analysis

## 📋 Analysis Date
2026-02-09

## 🎯 Analysis Scope

1. **Pod Disruption Budget (PDB) Configuration**
2. **Horizontal Pod Autoscaler (HPA) Metrics**
3. **StatefulSets and Persistent Volume Handling**

---

## 1. Pod Disruption Budget (PDB) Configuration

### Current Configuration

**Location:** `helm/environments/production/vendure-values.yaml`

**Current Settings:**
```yaml
podDisruptionBudget:
  enabled: true
  minAvailable: 1
```

**Deployment Configuration:**
- `replicaCount: 2` (2 replicas)
- `minReplicas: 2` (HPA minimum)
- `maxReplicas: 5` (HPA maximum)

**PDB Template:** `helm/vendure-stack/templates/vendure-pdb.yaml`
```yaml
spec:
  minAvailable: 1
```

---

### ⚠️ Issue Analysis

#### Issue 1: PDB May Be Too Strict for Cluster Upgrades

**Current Situation:**
- **Replicas:** 2
- **PDB minAvailable:** 1
- **Available for disruption:** 1 pod (50% of replicas)

**Problem:**
- During cluster upgrades, Kubernetes needs to drain nodes
- With `minAvailable: 1`, only 1 pod can be evicted at a time
- If you have 2 pods on 2 different nodes, you can drain one node
- But if both pods are on the same node, you **cannot drain that node** without violating PDB
- This can **block cluster upgrades** or node maintenance

**Impact if Missing:**
- ⚠️ **Upgrade Blocking:** Cannot drain nodes during Kubernetes upgrades
- ⚠️ **Maintenance Issues:** Cannot perform node maintenance
- ⚠️ **Rolling Updates:** May be slower than necessary
- ⚠️ **Node Draining:** May fail if pods are co-located

**What Should Be:**
```yaml
# Option 1: Use percentage (more flexible)
podDisruptionBudget:
  enabled: true
  minAvailable: 50%  # Allows 1 pod disruption when 2 replicas

# Option 2: Use maxUnavailable (better for upgrades)
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1  # Allows 1 pod to be unavailable
```

**Recommendation:**
- Use `maxUnavailable: 1` instead of `minAvailable: 1`
- This allows 1 pod to be unavailable during disruptions
- More flexible for upgrades and maintenance
- Still maintains availability (1 pod always running)

---

#### Issue 2: PDB Not Configured for Different Replica Counts

**Current Situation:**
- PDB is static: `minAvailable: 1`
- HPA can scale from 2 to 5 replicas
- PDB doesn't adapt to replica count changes

**Problem:**
- When HPA scales to 5 replicas, PDB still allows only 1 pod disruption
- This is actually **too restrictive** at higher replica counts
- Should allow more pods to be disrupted when more replicas exist

**Impact if Missing:**
- ⚠️ **Inefficient Scaling:** PDB doesn't adapt to HPA scaling
- ⚠️ **Unnecessary Restrictions:** Too strict at higher replica counts

**What Should Be:**
```yaml
# Use percentage-based PDB (adapts to replica count)
podDisruptionBudget:
  enabled: true
  minAvailable: 50%  # Adapts: 1/2, 2/4, 2/5, etc.
```

---

### ✅ Positive Aspects

1. **PDB is Enabled:** Good for production availability
2. **Minimum Availability:** Ensures at least 1 pod always running
3. **Matches Replica Count:** Works with 2 replicas minimum

---

## 2. Horizontal Pod Autoscaler (HPA) Metrics

### Current Configuration

**Location:** `helm/environments/production/vendure-values.yaml`

**Current Settings:**
```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 75
```

**HPA Template:** `helm/vendure-stack/templates/vendure-hpa.yaml`
```yaml
metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 75
```

---

### ⚠️ Issue Analysis

#### Issue 1: HPA Only Uses CPU/Memory Metrics

**Current Situation:**
- HPA only scales based on:
  - CPU utilization (70%)
  - Memory utilization (75%)
- **No request-based metrics** (requests per second, queue depth, etc.)

**Problem:**
- **I/O-Bound Workloads:** If Vendure is I/O-bound (database queries, file operations), CPU/memory may not reflect load
- **Request-Based Scaling:** No scaling based on HTTP request rate
- **Queue-Based Scaling:** No scaling based on job queue depth
- **Response Time:** No scaling based on response time metrics

**Impact if Missing:**
- ⚠️ **Under-Scaling:** May not scale up when CPU/memory is low but requests are high
- ⚠️ **Over-Scaling:** May scale up unnecessarily when CPU spikes but requests are low
- ⚠️ **I/O Bottlenecks:** Won't scale for database I/O or file I/O bottlenecks
- ⚠️ **Request Spikes:** Won't respond quickly to traffic spikes

**What Should Be:**
```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  metrics:
    # Resource metrics (existing)
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 75
    # Request-based metrics (NEW)
    - type: Pods
      pods:
        metric:
          name: http_requests_per_second
        target:
          type: AverageValue
          averageValue: "100"  # Scale when avg > 100 req/s per pod
    # Or use Prometheus metrics
    - type: Object
      object:
        metric:
          name: requests_per_second
        describedObject:
          apiVersion: v1
          kind: Service
          name: vendure
        target:
          type: Value
          value: "500"  # Scale when total > 500 req/s
```

**Recommendation:**
- Add **request rate metrics** (HTTP requests per second)
- Add **custom metrics** from Prometheus (if available)
- Consider **response time metrics** for better scaling decisions

---

#### Issue 2: No HPA Behavior Configuration

**Current Situation:**
- No `behavior` section in HPA
- Uses default scaling behavior
- No control over scale-up/scale-down speed

**Problem:**
- **Rapid Scaling:** May scale too quickly, causing cost spikes
- **Slow Scale-Down:** May not scale down quickly enough, wasting resources
- **Oscillation:** May oscillate between replica counts

**Impact if Missing:**
- ⚠️ **Cost Spikes:** Rapid scale-up can cause unexpected costs
- ⚠️ **Resource Waste:** Slow scale-down wastes resources
- ⚠️ **Unstable Scaling:** Oscillation between replica counts

**What Should Be:**
```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 75
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300  # 5 minutes before scale down
      policies:
        - type: Pods
          value: 1
          periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 60   # 1 minute before scale up
      policies:
        - type: Pods
          value: 1
          periodSeconds: 30
        - type: Percent
          value: 100
          periodSeconds: 60
```

---

#### Issue 3: No Custom Metrics Support

**Current Situation:**
- HPA template doesn't support custom metrics
- Only supports Resource metrics (CPU/memory)

**Problem:**
- Cannot use Prometheus metrics for scaling
- Cannot use application-specific metrics
- Limited to basic resource utilization

**Impact if Missing:**
- ⚠️ **Limited Scaling Intelligence:** Can't use application metrics
- ⚠️ **No Business Logic:** Can't scale based on business metrics (orders, users, etc.)

**What Should Be:**
- Add support for custom metrics in HPA template
- Integrate with Prometheus Adapter for custom metrics
- Allow configuration of custom metrics in values file

---

### ✅ Positive Aspects

1. **HPA is Enabled:** Good for automatic scaling
2. **Reasonable Thresholds:** 70% CPU, 75% memory are reasonable
3. **Appropriate Range:** 2-5 replicas is good for production

---

## 3. StatefulSets and Persistent Volume Handling

### Current Configuration

**Finding:** ✅ **NO STATEFULSETS FOUND**

**Vendure Application:**
- Uses **Deployment** (stateless)
- No persistent volumes required
- No StatefulSet needed

**Database:**
- **External RDS MySQL** (production)
- No in-cluster StatefulSet
- No persistent volume management needed

**Redis:**
- **External Redis Cloud** (production)
- No in-cluster StatefulSet
- No persistent volume management needed

**Monitoring:**
- Prometheus uses **StatefulSet** (in monitoring namespace)
- Has persistent volumes for metrics storage
- **Not part of Vendure deployment**

---

### ✅ Analysis Result: No Issues Found

**Status:** ✅ **NOT APPLICABLE**

**Reason:**
- Vendure is a **stateless application** (Deployment)
- Database and Redis are **external services** (RDS, Redis Cloud)
- No StatefulSets in Vendure deployment
- No persistent volume management needed for Vendure

**Note:**
- If you add StatefulSets in the future (e.g., for file storage), you'll need to:
  - Handle PVC lifecycle correctly
  - Configure proper volumeClaimTemplates
  - Handle StatefulSet scaling carefully (scale down requires manual PVC cleanup)
  - Ensure PVCs are backed up (Velero handles this)

---

## 📊 Summary of Issues

| Issue | Severity | Impact | Status |
|-------|----------|--------|--------|
| PDB too strict for upgrades | 🟡 **MEDIUM** | May block cluster upgrades | ⚠️ Needs Fix |
| PDB not percentage-based | 🟡 **LOW** | Doesn't adapt to HPA scaling | ⚠️ Should Fix |
| HPA only CPU/memory | 🟡 **MEDIUM** | May not scale for I/O-bound workloads | ⚠️ Should Fix |
| No HPA behavior config | 🟡 **LOW** | No control over scaling speed | ⚠️ Should Fix |
| No custom metrics | 🟡 **LOW** | Limited scaling intelligence | ⚠️ Nice to Have |
| StatefulSets handling | ✅ **N/A** | No StatefulSets in Vendure | ✅ Not Applicable |

---

## 🔧 Recommended Fixes

### Fix 1: Update PDB Configuration

**File:** `helm/environments/production/vendure-values.yaml`

**Change:**
```yaml
# Before
podDisruptionBudget:
  enabled: true
  minAvailable: 1

# After
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1  # More flexible for upgrades
  # OR use percentage
  # minAvailable: 50%  # Adapts to replica count
```

**Also update template:** `helm/vendure-stack/templates/vendure-pdb.yaml`
```yaml
spec:
  {{- if .Values.vendure.podDisruptionBudget.maxUnavailable }}
  maxUnavailable: {{ .Values.vendure.podDisruptionBudget.maxUnavailable }}
  {{- else if .Values.vendure.podDisruptionBudget.minAvailable }}
  minAvailable: {{ .Values.vendure.podDisruptionBudget.minAvailable }}
  {{- end }}
```

---

### Fix 2: Add Request-Based Metrics to HPA

**File:** `helm/vendure-stack/templates/vendure-hpa.yaml`

**Add support for custom metrics:**
```yaml
metrics:
  # Existing resource metrics
  {{- if .Values.vendure.autoscaling.targetCPUUtilizationPercentage }}
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: {{ .Values.vendure.autoscaling.targetCPUUtilizationPercentage }}
  {{- end }}
  {{- if .Values.vendure.autoscaling.targetMemoryUtilizationPercentage }}
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: {{ .Values.vendure.autoscaling.targetMemoryUtilizationPercentage }}
  {{- end }}
  # Add custom metrics if configured
  {{- if .Values.vendure.autoscaling.customMetrics }}
  {{- range .Values.vendure.autoscaling.customMetrics }}
  - {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- end }}
```

**Add to values:**
```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70
  targetMemoryUtilizationPercentage: 75
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
        - type: Pods
          value: 1
          periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 60
      policies:
        - type: Pods
          value: 1
          periodSeconds: 30
  # Custom metrics (optional)
  customMetrics: []
```

---

## ✅ Verification Checklist

After fixes:

- [ ] PDB uses `maxUnavailable` or percentage-based `minAvailable`
- [ ] PDB allows node draining during upgrades
- [ ] HPA includes request-based metrics (if needed)
- [ ] HPA behavior configured for controlled scaling
- [ ] Custom metrics support added (if needed)
- [ ] StatefulSets reviewed (if added in future)

---

**Analysis Complete** ✅


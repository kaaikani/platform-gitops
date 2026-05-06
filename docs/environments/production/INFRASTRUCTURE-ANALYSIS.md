# Infrastructure & Cost Analysis - Vendure Helm Configuration

## 📋 Analysis Date
2026-02-09

## 🎯 Requirements Check

### Requirement 1: Spot Instance Reliability
**Requirement:** Vendure should run on **ON-DEMAND** instances (not spot) to handle disruptions gracefully, especially with longer startup times.

**Current Status:** ❌ **NON-COMPLIANT**

### Requirement 2: Karpenter Configuration
**Requirement:** Karpenter should only provision:
- **Instance Family:** Only `t` family ✅
- **Instance Sizes:** Only `small` and `medium` (not large, xlarge)
- **Capacity Type:** Should be configurable (on-demand for Vendure)

**Current Status:** ⚠️ **PARTIALLY COMPLIANT**

---

## 🔍 Detailed Analysis

### 1. Spot Instance Configuration

#### ❌ Issue Found: Vendure Running on Spot Instances

**Location:** `helm/environments/production/vendure-values.yaml`

**Current Configuration (Lines 106-115):**
```yaml
# Run on SPOT instances (application can handle restarts)
nodeSelector:
  node-type: spot
  workload: application

tolerations:
  - key: "spot"
    operator: "Equal"
    value: "true"
    effect: "NoSchedule"
```

**Problem:**
- Vendure pods are configured to run on spot instances
- Spot instances can be terminated with 2-minute notice
- Vendure has startup time of 60-120 seconds (initialDelaySeconds: 60-120)
- This creates risk of service disruption during spot termination

**Impact if Missing:**
- ⚠️ **Service Disruption:** If spot instance is terminated, Vendure pods will be evicted
- ⚠️ **Startup Time Risk:** With 60-120 second startup time, there's a window where service is unavailable
- ⚠️ **User Impact:** Customers may experience 503 errors during spot termination
- ⚠️ **No Graceful Handling:** Pods may not have time to complete in-flight requests

**What Should Be:**
```yaml
# Run on ON-DEMAND instances (reliable, no interruptions)
nodeSelector:
  node-type: on-demand
  workload: application

tolerations: []  # No spot tolerations needed
```

---

#### ❌ Issue Found: EKS Node Group Using Spot Instances

**Location:** `helm/environments/production/eks-nodegroups.yaml`

**Current Configuration (Lines 102-111):**
```yaml
- name: app-spot
  instanceTypes:
    - t3a.medium
    - t3.medium
    - t3a.large
  
  # SPOT Instance (70-90% cheaper)
  spot: true
```

**Problem:**
- Node group is explicitly configured as spot instances
- This node group is intended for Vendure application

**Impact if Missing:**
- ⚠️ **Node Termination:** AWS can terminate spot instances with 2-minute notice
- ⚠️ **Pod Eviction:** All pods on terminated node will be evicted
- ⚠️ **Service Downtime:** During pod rescheduling and startup

**What Should Be:**
```yaml
- name: app-on-demand
  instanceTypes:
    - t3.medium
    - t3.small
  
  # ON-DEMAND: Never interrupted by AWS
  spot: false
```

---

### 2. Karpenter Configuration

#### ⚠️ Issue Found: Karpenter Allows Both Spot and On-Demand

**Location:** `helm/karpenter/nodepool-application.yaml`

**Current Configuration (Lines 26-29):**
```yaml
# Capacity Type - Prefer Spot for cost savings
- key: karpenter.sh/capacity-type
  operator: In
  values: ["spot", "on-demand"]
```

**Problem:**
- Karpenter can provision both spot and on-demand instances
- For Vendure, we want only on-demand for reliability

**Impact if Missing:**
- ⚠️ **Unpredictable Behavior:** Karpenter might provision spot instances when on-demand is preferred
- ⚠️ **Cost vs Reliability Trade-off:** May choose cheaper spot instances, causing reliability issues
- ⚠️ **Inconsistent Infrastructure:** Mix of spot and on-demand nodes

**What Should Be:**
```yaml
# Capacity Type - ON-DEMAND only for Vendure reliability
- key: karpenter.sh/capacity-type
  operator: In
  values: ["on-demand"]
```

---

#### ⚠️ Issue Found: Karpenter Allows Large and XLarge Instances

**Location:** `helm/karpenter/nodepool-application.yaml`

**Current Configuration (Lines 39-41):**
```yaml
# Instance Sizes
- key: karpenter.k8s.aws/instance-size
  operator: In
  values: ["small", "medium", "large", "xlarge"]
```

**Problem:**
- Karpenter can provision large and xlarge instances
- Requirement is to only allow small and medium

**Impact if Missing:**
- ⚠️ **Cost Overrun:** Karpenter might provision expensive large/xlarge instances
- ⚠️ **Capacity Imbalance:** Large instances may be over-provisioned for workload
- ⚠️ **Budget Exceeded:** Unexpected costs from larger instance types

**What Should Be:**
```yaml
# Instance Sizes - Only small and medium
- key: karpenter.k8s.aws/instance-size
  operator: In
  values: ["small", "medium"]
```

---

#### ✅ Correct: Karpenter Instance Family Constraint

**Location:** `helm/karpenter/nodepool-application.yaml`

**Current Configuration (Lines 31-34):**
```yaml
# Instance Categories - Only t-series (burstable) instances allowed
- key: karpenter.k8s.aws/instance-category
  operator: In
  values: ["t"]
```

**Status:** ✅ **CORRECT**
- Only `t` family instances are allowed
- This matches the requirement

---

### 3. Additional Findings

#### ⚠️ Issue: Node Labels Mismatch

**Location:** `helm/environments/production/vendure-values.yaml` vs `helm/environments/production/eks-nodegroups.yaml`

**Problem:**
- Vendure values expect: `node-type: spot`
- If we change to on-demand, node group labels need to match

**Current Node Group Labels (eks-nodegroups.yaml, line 125-129):**
```yaml
labels:
  node-type: spot
  workload: application
  environment: production
  lifecycle: spot
```

**What Should Be (for on-demand):**
```yaml
labels:
  node-type: on-demand
  workload: application
  environment: production
  lifecycle: on-demand
```

---

#### ⚠️ Issue: Node Taints Mismatch

**Location:** `helm/environments/production/eks-nodegroups.yaml`

**Current Configuration (Lines 132-135):**
```yaml
# Taint for application workloads
taints:
  - key: "spot"
    value: "true"
    effect: "NoSchedule"
```

**Problem:**
- Node group has spot taint
- If changing to on-demand, taint should be removed or changed

**What Should Be:**
```yaml
# No taints for on-demand nodes (or use different taint if needed)
taints: []
```

---

## 📊 Summary of Issues

| Issue | Location | Severity | Impact |
|-------|----------|----------|--------|
| Vendure on spot instances | `vendure-values.yaml:106-115` | 🔴 **CRITICAL** | Service disruption risk |
| Node group using spot | `eks-nodegroups.yaml:111` | 🔴 **CRITICAL** | Node termination risk |
| Karpenter allows spot | `nodepool-application.yaml:29` | 🟡 **HIGH** | Unpredictable provisioning |
| Karpenter allows large/xlarge | `nodepool-application.yaml:41` | 🟡 **MEDIUM** | Cost overrun risk |
| Node label mismatch | Multiple files | 🟡 **MEDIUM** | Pod scheduling issues |
| Node taint mismatch | `eks-nodegroups.yaml:132` | 🟡 **MEDIUM** | Pod scheduling issues |

---

## 🚨 Impact Assessment

### If Issues Are Not Fixed:

#### 1. **Service Reliability Issues**
- **Spot Termination:** AWS can terminate spot instances with 2-minute notice
- **Pod Eviction:** Vendure pods will be forcefully evicted
- **Startup Time:** 60-120 second startup time creates service gap
- **User Impact:** Customers experience 503 errors, failed requests
- **Business Impact:** Lost sales, poor user experience

#### 2. **Cost Management Issues**
- **Unexpected Costs:** Karpenter might provision expensive large/xlarge instances
- **Budget Overrun:** No constraints on instance sizes
- **Capacity Imbalance:** Over-provisioned resources

#### 3. **Operational Issues**
- **Inconsistent Infrastructure:** Mix of spot and on-demand nodes
- **Scheduling Problems:** Pods may not schedule if labels/taints don't match
- **Debugging Difficulty:** Hard to predict which instance type will be provisioned

---

## ✅ Required Changes Summary

### 1. Change Vendure to On-Demand Instances

**Files to Update:**
- `helm/environments/production/vendure-values.yaml`
  - Change `nodeSelector.node-type` from `spot` to `on-demand`
  - Remove spot tolerations

- `helm/environments/production/eks-nodegroups.yaml`
  - Change `spot: true` to `spot: false`
  - Update node labels from `spot` to `on-demand`
  - Remove spot taints
  - Rename node group from `app-spot` to `app-on-demand`

### 2. Fix Karpenter Configuration

**Files to Update:**
- `helm/karpenter/nodepool-application.yaml`
  - Change capacity type to only `["on-demand"]`
  - Change instance sizes to only `["small", "medium"]`
  - Update node labels to `on-demand` (if using Karpenter for Vendure)

---

## 📝 Configuration Checklist

After making changes, verify:

- [ ] Vendure `nodeSelector` uses `on-demand` (not `spot`)
- [ ] Vendure has no spot tolerations
- [ ] EKS node group has `spot: false`
- [ ] EKS node group labels use `on-demand` (not `spot`)
- [ ] EKS node group has no spot taints
- [ ] Karpenter capacity type is only `on-demand`
- [ ] Karpenter instance sizes are only `small` and `medium`
- [ ] Karpenter instance category is only `t`
- [ ] All node labels match between node groups and pod selectors
- [ ] All taints match pod tolerations

---

## 🔄 Migration Path

If currently running on spot instances:

1. **Create new on-demand node group** (don't delete spot yet)
2. **Update Helm values** to use on-demand
3. **Rolling update** Vendure deployment
4. **Verify** pods are running on on-demand nodes
5. **Drain and delete** old spot node group

---

**Analysis Complete** ✅


# Cost-Optimized EKS Deployment Guide

**Target Budget: ~$4/day (~$120/month)**

## Cost Breakdown

| Component | Hourly | Daily | Monthly | Notes |
|-----------|--------|-------|---------|-------|
| EKS Control Plane | $0.10 | $2.40 | $72.00 | Fixed cost |
| Spot Instance (t3a.medium) | ~$0.013 | ~$0.31 | ~$9.50 | 2 vCPU, 4GB RAM |
| ALB (shared) | ~$0.025 | ~$0.60 | ~$18.00 | + LCU charges |
| EBS Storage (gp3, 43GB) | - | ~$0.11 | ~$3.50 | 30GB node + 13GB PVs |
| **TOTAL** | - | **~$3.42** | **~$103** | Under $4/day target |

*Note: RDS and Redis Cloud are external services - costs not included*

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS EKS Cluster                          │
│                    (ap-south-1)                             │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────┐   │
│  │           Spot Node (t3a.medium - 4GB)               │   │
│  │  ┌─────────────────┐  ┌────────────────────────┐     │   │
│  │  │    Vendure      │  │   Monitoring Stack     │     │   │
│  │  │  (384Mi-768Mi)  │  │  Prometheus (256Mi)    │     │   │
│  │  │   1 replica     │  │  Grafana (64Mi)        │     │   │
│  │  │   (HPA: 1-2)    │  │  AlertManager (32Mi)   │     │   │
│  │  └─────────────────┘  └────────────────────────┘     │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌────────────────────────────────────────────────────┐     │
│  │        Second Spot Node (ONLY when scaled)         │     │
│  │        Auto-scales at 80% CPU / 85% Memory         │     │
│  └────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
                    ┌───────────────┐
                    │   AWS ALB     │
                    │ (Shared)      │
                    └───────────────┘
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
     api.kaaikani.co.in          test.avsecomhub.com
```

## Deployment Steps

### Step 1: Delete Existing Node Group

```bash
# Get cluster name
CLUSTER_NAME=$(kubectl config current-context | cut -d'/' -f2 | cut -d'.' -f1)
echo "Cluster: $CLUSTER_NAME"

# List existing node groups
eksctl get nodegroup --cluster=$CLUSTER_NAME

# Delete old node group (replace <OLD_NODEGROUP_NAME>)
eksctl delete nodegroup \
  --cluster=$CLUSTER_NAME \
  --name=<OLD_NODEGROUP_NAME> \
  --drain \
  --wait
```

### Step 2: Create Cost-Optimized Spot Node Group

```bash
# Edit the config file first - set your cluster name
cd /home/adminuser/Desktop/vendure/K8s/Admin-ui/helm/eks-node-config

# Create the spot node group
eksctl create nodegroup -f spot-nodegroup.yaml

# Verify node is ready
kubectl get nodes -l node-type=spot
```

### Step 3: Update Vendure Deployment

```bash
cd /home/adminuser/Desktop/vendure/K8s/Admin-ui

# Upgrade Vendure with cost-optimized values
helm upgrade vendure ./helm/vendure-stack \
  -n vendure-production \
  -f helm/vendure-stack/values-production-cost-optimized.yaml \
  --wait

# Verify deployment
kubectl get pods -n vendure-production
kubectl get hpa -n vendure-production
```

### Step 4: Update Monitoring Stack

```bash
# Upgrade monitoring stack with cost-optimized values
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring \
  -f helm/monitoring-stack/values-cost-optimized.yaml \
  --set grafana.adminPassword=<YOUR_GRAFANA_PASSWORD> \
  --wait

# Verify monitoring pods
kubectl get pods -n monitoring
```

### Step 5: Verify Everything is Running

```bash
# Check all pods
kubectl get pods -A | grep -E "(vendure|monitoring)"

# Check resource usage
kubectl top nodes
kubectl top pods -n vendure-production
kubectl top pods -n monitoring

# Check HPA status
kubectl get hpa -n vendure-production

# Test application health
kubectl exec -n vendure-production deploy/vendure-vendure-stack-vendure -- curl -s localhost:3000/health
```

## Quick One-Liner Deployment

```bash
# Full deployment in one command (after editing cluster name in spot-nodegroup.yaml)
eksctl delete nodegroup --cluster=vendure-cluster --name=<OLD_NODEGROUP> --drain && \
eksctl create nodegroup -f helm/eks-node-config/spot-nodegroup.yaml && \
helm upgrade vendure ./helm/vendure-stack -n vendure-production -f helm/vendure-stack/values-production-cost-optimized.yaml && \
helm upgrade prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring -f helm/monitoring-stack/values-cost-optimized.yaml --set grafana.adminPassword=<PASSWORD>
```

## Scaling Behavior

| Condition | Action |
|-----------|--------|
| CPU < 80% AND Memory < 85% | Stay at 1 replica |
| CPU >= 80% OR Memory >= 85% | Scale to 2 replicas (after 1 min) |
| Load decreases | Scale down to 1 replica (after 2 min) |

## Monitoring Access

```bash
# Grafana (after deployment)
kubectl port-forward svc/prometheus-stack-grafana -n monitoring 3000:80
# Open: http://localhost:3000 (admin / <YOUR_PASSWORD>)

# Prometheus
kubectl port-forward svc/prometheus-stack-kube-prom-prometheus -n monitoring 9090:9090
# Open: http://localhost:9090
```

## Spot Instance Considerations

**Pros:**
- 60-70% cost savings vs On-Demand
- Same performance as regular instances

**Cons:**
- Can be interrupted with 2-minute warning
- Less predictable availability

**Mitigations:**
1. Multiple instance types configured for fallback
2. Multiple availability zones
3. Alerts for spot termination warnings
4. Application is stateless (uses external RDS/Redis)

## Troubleshooting

### Pod Pending (Insufficient Resources)
```bash
# Check node resources
kubectl describe node -l node-type=spot | grep -A5 "Allocated resources"

# If needed, manually scale node group
eksctl scale nodegroup --cluster=vendure-cluster --name=spot-ng-cost-optimized --nodes=2
```

### Spot Instance Terminated
```bash
# Check for new node
kubectl get nodes -w

# Pods will auto-reschedule to new node
kubectl get pods -n vendure-production -w
```

### High Memory Usage
```bash
# Check which pods are using most memory
kubectl top pods -n vendure-production --sort-by=memory

# Consider temporarily increasing node count
eksctl scale nodegroup --cluster=vendure-cluster --name=spot-ng-cost-optimized --nodes=2
```

## Cost Monitoring

```bash
# Check current spot prices
aws ec2 describe-spot-price-history \
  --instance-types t3a.medium t3.medium \
  --region ap-south-1 \
  --start-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --product-descriptions "Linux/UNIX" \
  --query 'SpotPriceHistory[*].[InstanceType,SpotPrice,AvailabilityZone]' \
  --output table
```

## Files Created

| File | Purpose |
|------|---------|
| `helm/eks-node-config/spot-nodegroup.yaml` | eksctl config for spot nodes |
| `helm/vendure-stack/values-production-cost-optimized.yaml` | Vendure helm values |
| `helm/monitoring-stack/values-cost-optimized.yaml` | Monitoring stack values |

## Rollback (If Needed)

```bash
# Rollback to previous Vendure deployment
helm rollback vendure -n vendure-production

# Rollback to previous monitoring stack
helm rollback prometheus-stack -n monitoring

# Create on-demand node group if spot issues
eksctl create nodegroup \
  --cluster=vendure-cluster \
  --name=ondemand-fallback \
  --node-type=t3a.medium \
  --nodes=1 \
  --nodes-min=1 \
  --nodes-max=2
```

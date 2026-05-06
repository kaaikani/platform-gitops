# Karpenter Configuration for Vendure SaaS

## Overview

This directory contains Karpenter NodePool and EC2NodeClass configurations for the Vendure SaaS platform running on AWS EKS.

## Prerequisites

Before applying these configurations, ensure:

1. **Karpenter is installed** via Helm:
   ```bash
   helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
     --version "1.2.1" \
     --namespace kube-system \
     --set "settings.clusterName=vendure-prod" \
     --set "settings.interruptionQueue=vendure-prod" \
     --set "serviceAccount.create=false" \
     --set "serviceAccount.name=karpenter"
   ```

2. **IAM Roles are created** via CloudFormation:
   ```bash
   aws cloudformation deploy \
     --stack-name "Karpenter-vendure-prod" \
     --template-file cloudformation.yaml \
     --capabilities CAPABILITY_NAMED_IAM \
     --parameter-overrides "ClusterName=vendure-prod"
   ```

3. **Subnets and Security Groups are tagged**:
   ```bash
   # Tag public subnets
   aws ec2 create-tags --resources subnet-xxx \
     --tags Key=karpenter.sh/discovery,Value=vendure-prod

   # Tag cluster security group
   aws ec2 create-tags --resources sg-xxx \
     --tags Key=karpenter.sh/discovery,Value=vendure-prod
   ```

4. **aws-auth ConfigMap includes Karpenter node role**:
   ```yaml
   - rolearn: arn:aws:iam::149536454380:role/KarpenterNodeRole-vendure-prod
     groups:
     - system:bootstrappers
     - system:nodes
     username: system:node:{{EC2PrivateDNSName}}
   ```

## Files

| File | Description |
|------|-------------|
| `ec2nodeclass.yaml` | EC2 node configuration (AMI, subnets, security groups, EBS) |
| `nodepool-application.yaml` | NodePool for Vendure application workloads (spot instances) |
| `nodepool-monitoring.yaml` | NodePool for Prometheus/Grafana (on-demand, stable) |
| `kustomization.yaml` | Kustomize configuration for applying all resources |

## Apply Configuration

### Using Kustomize
```bash
kubectl apply -k helm/karpenter/
```

### Individual Files
```bash
kubectl apply -f helm/karpenter/ec2nodeclass.yaml
kubectl apply -f helm/karpenter/nodepool-application.yaml
kubectl apply -f helm/karpenter/nodepool-monitoring.yaml
```

## NodePool Strategy

### Application Pool (Spot)
- **Purpose**: Run Vendure e-commerce workloads
- **Capacity**: Spot instances (70-90% cost savings)
- **Instance Types**: t3 small/medium/large/xlarge (t-series only)
- **Max Resources**: 50 vCPU, 100GB RAM
- **Consolidation**: Aggressive (1 minute)
- **Note**: Only t-series (burstable) instances allowed. Includes small instances for efficient bin-packing of smaller workloads

### Monitoring Pool (On-Demand)
- **Purpose**: Run Prometheus, Grafana, Loki
- **Capacity**: On-demand only (stability)
- **Instance Types**: t3/m5 small/medium
- **Max Resources**: 8 vCPU, 16GB RAM
- **Consolidation**: Conservative (24 hours)
- **Taint**: `dedicated=monitoring:NoSchedule`

## Workload Scheduling

### For Vendure Pods
Add this nodeSelector to schedule on application pool:
```yaml
nodeSelector:
  node-type: application
```

### For Monitoring Pods
Add nodeSelector and toleration:
```yaml
nodeSelector:
  node-type: monitoring
tolerations:
  - key: dedicated
    value: monitoring
    effect: NoSchedule
```

## Verification

```bash
# Check NodePools
kubectl get nodepools

# Check EC2NodeClass
kubectl get ec2nodeclasses

# Check NodeClaims (provisioned nodes)
kubectl get nodeclaims

# Check Karpenter logs
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f
```

## Karpenter Failover & Fallback Node Group

If the Karpenter controller crashes or AWS API throttles, no new nodes are provisioned. Production should keep a **managed node group** with the same labels (`node-group=app`) and **minSize ≥ 1** so app workloads can still schedule. See:

- **[KARPENTER-FAILOVER-STRATEGY.md](../environments/production/KARPENTER-FAILOVER-STRATEGY.md)** — Runbooks, capacity planning, and checklist.

---

## Troubleshooting

### Node Not Registering
1. Check if public IP is assigned (required for public subnet setup)
2. Verify aws-auth ConfigMap includes Karpenter node role
3. Check security group allows EKS control plane access

### Node Not Provisioning
1. Check Karpenter logs for errors
2. Verify subnet and security group tags
3. Ensure EC2NodeClass status is Ready

### Cost Optimization
1. Spot instances provide 70-90% savings
2. Consolidation removes underutilized nodes
3. Monitor with: `kubectl get nodeclaims -o wide`

## AWS Resources

| Resource | Value |
|----------|-------|
| Cluster | vendure-prod |
| Region | ap-south-1 |
| VPC | vpc-09d5a8fe67e99da87 |
| Node Role | KarpenterNodeRole-vendure-prod |
| Controller Role | KarpenterControllerRole-vendure-prod |

# Kubernetes Version Upgrade Guide - Zero Downtime Strategy

## 📋 Overview

This guide provides a comprehensive, zero-downtime strategy for upgrading your EKS Kubernetes cluster from one version to another.

**Current Setup:**
- Cluster: `vendure-prod`
- Region: `ap-south-1`
- Current K8s Version: Check with `kubectl version` or `aws eks describe-cluster --name vendure-prod`

**Upgrade Strategy:**
- **Control Plane**: AWS manages (upgrade via AWS Console/CLI)
- **Node Groups**: Blue-Green deployment (zero downtime)
- **Applications**: Rolling updates with health checks

---

## 🎯 Upgrade Principles

### 1. **Zero Downtime**
- Use blue-green node group strategy
- Maintain application availability during upgrade
- Health checks ensure traffic only routes to healthy pods

### 2. **Rollback Ready**
- Keep old node group until upgrade is verified
- Maintain backups before upgrade
- Document rollback procedures

### 3. **Gradual Migration**
- Upgrade control plane first
- Create new node group with new K8s version
- Migrate workloads gradually
- Verify at each step

### 4. **Testing First**
- Test in non-production environment
- Verify application compatibility
- Check Helm chart compatibility

---

## 📊 EKS Version Compatibility

### Supported Upgrade Paths

AWS EKS supports upgrading **one minor version at a time**:

```
1.28 → 1.29 → 1.30 → 1.31 → 1.32 → 1.33
```

**Example:**
- Current: 1.30
- Target: 1.32
- Path: 1.30 → 1.31 → 1.32 (two separate upgrades)

### Version Support Lifecycle

- **Current**: Latest 3 versions (e.g., 1.31, 1.32, 1.33)
- **Deprecated**: 1 version (6 months notice)
- **End of Life**: No longer supported

**Check current versions:**
```bash
aws eks describe-addon-versions --addon-name vpc-cni --query 'addons[0].addonVersions[0].compatibilities[*].clusterVersion' --output text
```

---

## 🔍 Pre-Upgrade Checklist

### 1. Check Current Versions

```bash
# Cluster version
aws eks describe-cluster --name vendure-prod --query 'cluster.version' --output text

# Node group versions
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.kubeletVersion}{"\n"}{end}'

# kubectl version
kubectl version --client --short

# Helm charts compatibility
helm list -A
```

### 2. Verify Application Compatibility

```bash
# Check if applications support target K8s version
# Review Helm chart requirements
helm show chart <chart-name> | grep kubeVersion

# Test in non-production first
```

### 3. Backup Everything

```bash
# Backup Kubernetes resources
./helm/environments/production/backup-before-upgrade.sh

# Verify Velero backups are recent
velero backup get

# RDS backups (automated, but verify)
aws rds describe-db-snapshots --db-instance-identifier <rds-id>
```

### 4. Check Resource Availability

```bash
# Ensure you have capacity for new node group
kubectl top nodes
kubectl top pods -A

# Check if you can scale up temporarily
```

### 5. Review Breaking Changes

```bash
# Check Kubernetes release notes
# https://kubernetes.io/docs/setup/release/notes/

# Check EKS release notes
# https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
```

---

## 🚀 Upgrade Procedure

### Phase 1: Control Plane Upgrade

**Duration:** 15-30 minutes (AWS managed, zero downtime)

```bash
# 1. Check available versions
aws eks describe-cluster --name vendure-prod --query 'cluster.version' --output text
aws eks list-versions --query 'versions' --output table

# 2. Upgrade control plane (one minor version at a time)
aws eks update-cluster-version \
  --name vendure-prod \
  --region ap-south-1 \
  --kubernetes-version 1.31  # Target version

# 3. Monitor upgrade status
aws eks describe-cluster --name vendure-prod --query 'cluster.status' --output text
# Wait until status is "ACTIVE"

# 4. Verify control plane version
aws eks describe-cluster --name vendure-prod --query 'cluster.version' --output text
```

**⚠️ Important:**
- Control plane upgrade is **non-disruptive** (AWS managed)
- Applications continue running on old node groups
- Upgrade takes 15-30 minutes
- **Do not upgrade node groups until control plane is ACTIVE**

---

### Phase 2: Node Group Upgrade (Blue-Green)

**Duration:** 30-60 minutes (zero downtime)

#### Step 1: Create New Node Group with New K8s Version

```bash
# Create new node group with target K8s version
eksctl create nodegroup \
  --cluster=vendure-prod \
  --region=ap-south-1 \
  --name=vendure-nodes-v131 \
  --instance-types=t3.medium,t3a.medium \
  --nodes=2 \
  --nodes-min=2 \
  --nodes-max=4 \
  --node-volume-size=20 \
  --node-volume-type=gp3 \
  --managed \
  --spot \
  --kubelet-version=1.31.0 \
  --labels="node-type=app,kubernetes.io/version=1.31" \
  --taints="workload=app:NoSchedule" \
  --asg-access
```

#### Step 2: Wait for New Nodes to be Ready

```bash
# Watch nodes come online
kubectl get nodes -w

# Verify new nodes are Ready
kubectl get nodes -l kubernetes.io/version=1.31
```

#### Step 3: Update Application Deployments to Use New Nodes

```bash
# Remove taints from new nodes (if needed)
kubectl taint nodes -l kubernetes.io/version=1.31 workload=app:NoSchedule-

# Update node selectors/affinity to prefer new nodes
# (This is done via Helm values - see below)
```

#### Step 4: Gradually Migrate Workloads

```bash
# Option A: Use Pod Disruption Budgets (automatic)
# PDBs ensure minimum pods are always running

# Option B: Manual migration (more control)
# 1. Cordon old nodes (prevent new pods)
kubectl cordon <old-node-name>

# 2. Drain old nodes (move pods to new nodes)
kubectl drain <old-node-name> --ignore-daemonsets --delete-emptydir-data --grace-period=300

# 3. Verify pods migrated successfully
kubectl get pods -o wide
```

#### Step 5: Verify Applications on New Nodes

```bash
# Check all pods are running
kubectl get pods -A

# Verify application health
kubectl get ingress -A
curl https://your-app-url/health

# Check metrics
kubectl top nodes
kubectl top pods -A
```

#### Step 6: Delete Old Node Group

```bash
# Only after verifying everything works!

# 1. Cordon all old nodes
kubectl cordon <old-node-1>
kubectl cordon <old-node-2>

# 2. Drain all old nodes
kubectl drain <old-node-1> --ignore-daemonsets --delete-emptydir-data
kubectl drain <old-node-2> --ignore-daemonsets --delete-emptydir-data

# 3. Delete old node group
eksctl delete nodegroup \
  --cluster=vendure-prod \
  --name=vendure-nodes-v130 \
  --drain \
  --wait
```

---

### Phase 3: Update Add-ons and Tools

```bash
# 1. Update kubectl to match cluster version
# Download matching kubectl version
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# 2. Update Helm charts (if needed)
helm repo update

# 3. Upgrade Helm releases (if charts support new K8s version)
helm upgrade vendure ./helm/vendure-stack \
  -n vendure-production \
  -f helm/environments/production/vendure-values.yaml

# 4. Update EKS add-ons (if needed)
aws eks update-addon \
  --cluster-name vendure-prod \
  --addon-name vpc-cni \
  --addon-version <latest-compatible-version> \
  --region ap-south-1
```

---

## 🔄 Rollback Procedure

### If Upgrade Fails

#### 1. Rollback Node Groups

```bash
# If new node group has issues, delete it
eksctl delete nodegroup \
  --cluster=vendure-prod \
  --name=vendure-nodes-v131 \
  --drain \
  --wait

# Old node group should still be running
# Verify old nodes are healthy
kubectl get nodes
```

#### 2. Rollback Control Plane (if needed)

**⚠️ Warning:** Control plane rollback is **complex** and may require AWS support.

```bash
# Contact AWS Support for control plane rollback
# Or restore from backup (if available)
```

#### 3. Restore from Backup

```bash
# Restore Kubernetes resources from Velero
velero restore create --from-backup <backup-name>

# Or restore from manual backup
kubectl apply -f backup-before-upgrade.yaml
```

---

## 📋 Post-Upgrade Verification

### 1. Verify Cluster Health

```bash
# Check all nodes
kubectl get nodes

# Check all pods
kubectl get pods -A

# Check system components
kubectl get pods -n kube-system
```

### 2. Verify Application Health

```bash
# Check application endpoints
curl https://your-app-url/health

# Check logs for errors
kubectl logs -n vendure-production -l app=vendure --tail=100

# Check metrics
kubectl top nodes
kubectl top pods -A
```

### 3. Verify Monitoring

```bash
# Check Prometheus
kubectl get pods -n monitoring

# Check Grafana
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

# Verify metrics are being collected
```

### 4. Performance Testing

```bash
# Run load tests
# Verify response times
# Check resource usage
```

---

## 🛠️ Automation Scripts

See:
- `./helm/environments/production/upgrade-kubernetes.sh` - Automated upgrade script
- `./helm/environments/production/backup-before-upgrade.sh` - Pre-upgrade backup
- `./helm/environments/production/verify-upgrade.sh` - Post-upgrade verification

---

## 📚 Best Practices

### 1. **Upgrade Frequency**
- **Recommended**: Every 3-6 months
- **Minimum**: Before version goes EOL
- **Maximum**: Stay within 2 minor versions of latest

### 2. **Testing Strategy**
- Test in non-production first
- Use canary deployments
- Monitor for 24-48 hours after upgrade

### 3. **Communication**
- Notify team before upgrade
- Schedule during low-traffic periods
- Have rollback plan ready

### 4. **Documentation**
- Document current versions
- Track upgrade history
- Note any issues encountered

---

## 🚨 Common Issues & Solutions

### Issue 1: Pods Not Scheduling on New Nodes

**Solution:**
```bash
# Check node labels and selectors
kubectl get nodes --show-labels
kubectl get pods -o wide

# Update node selectors in Helm values
# Or remove taints
kubectl taint nodes -l kubernetes.io/version=1.31 workload=app:NoSchedule-
```

### Issue 2: Applications Failing After Upgrade

**Solution:**
```bash
# Check application logs
kubectl logs -n vendure-production -l app=vendure

# Check if Helm chart needs update
helm show chart <chart-name>

# Rollback Helm release if needed
helm rollback vendure -n vendure-production
```

### Issue 3: Control Plane Upgrade Stuck

**Solution:**
```bash
# Check cluster status
aws eks describe-cluster --name vendure-prod

# Contact AWS Support if stuck > 1 hour
# Or check AWS Console for errors
```

---

## 📞 Support & Resources

- **AWS EKS Documentation**: https://docs.aws.amazon.com/eks/
- **Kubernetes Release Notes**: https://kubernetes.io/docs/setup/release/notes/
- **EKS Upgrade Guide**: https://docs.aws.amazon.com/eks/latest/userguide/update-cluster.html
- **AWS Support**: For control plane issues

---

## ✅ Upgrade Checklist

- [ ] Pre-upgrade backup completed
- [ ] Current versions documented
- [ ] Target version compatibility verified
- [ ] Team notified
- [ ] Control plane upgraded
- [ ] New node group created
- [ ] Workloads migrated
- [ ] Applications verified
- [ ] Old node group deleted
- [ ] Post-upgrade verification complete
- [ ] Documentation updated

---

**Last Updated:** 2026-02-09
**Next Review:** 2026-05-09


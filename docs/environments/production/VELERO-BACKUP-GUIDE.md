# Velero Backup Guide

## Overview

Velero backs up Kubernetes resources and persistent volumes to S3 with:
- **Daily backups** at 2 AM UTC (7:30 AM IST)
- **7-day retention** (automatic cleanup)
- **Compression enabled** (50-70% size reduction)
- **S3 versioning enabled** (protects against accidental deletion)
- **Encryption enabled** (AES256)

## Quick Start

### 1. Setup S3 Bucket and IRSA

```bash
./helm/environments/production/setup-velero-s3.sh
```

This script:
- Creates S3 bucket: `vendure-velero-backups`
- Enables versioning
- Enables encryption
- Sets lifecycle policies (cost optimization)
- Creates IRSA for S3 access

### 2. Update Velero Values with Role ARN

After running the setup script, it will show you the Role ARN. Update `velero-values.yaml`:

```yaml
serviceAccount:
  server:
    annotations:
      eks.amazonaws.com/role-arn: <ROLE_ARN_FROM_SCRIPT>
```

### 3. Install Velero

```bash
helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
helm repo update

helm install velero vmware-tanzu/velero \
  -n velero --create-namespace \
  -f helm/environments/production/velero-values.yaml
```

### 4. Verify Installation

```bash
./helm/environments/production/verify-velero-backup.sh
```

Or manually:
```bash
velero version
velero backup get
```

## What Gets Backed Up

### Namespaces
- `vendure-production`
- `vendure-test`
- `monitoring`
- `kubecost`

### Resources
- All Kubernetes objects (Deployments, Services, ConfigMaps, Secrets, etc.)
- Persistent volumes (EBS snapshots)
- Cluster-scoped resources

### Excluded
- `kube-system` (managed by AWS)
- `kube-public`
- `kube-node-lease`
- `default`

## Backup Schedule

- **Schedule**: Daily at 2 AM UTC (7:30 AM IST)
- **Retention**: 7 days (automatic cleanup)
- **Compression**: Enabled (automatic)
- **Storage**: S3 bucket `vendure-velero-backups`

## Cost Optimization

### Lifecycle Policy
- Old versions → Glacier after 30 days (96% cost reduction)
- Old backups deleted after 90 days
- Active backups deleted after 7 days

### Compression
- Velero automatically compresses backups
- Reduces storage by 50-70%

### Estimated Cost
- **Storage**: ~$2-3/month (100GB backups)
- **With Glacier**: ~$0.50/month (after 30 days)

## Common Operations

### View Backups

```bash
# List all backups
velero backup get

# View backup details
velero backup describe <backup-name>

# View backup logs
velero backup logs <backup-name>
```

### Create Manual Backup

```bash
# Backup specific namespace
velero backup create manual-backup \
  --include-namespaces vendure-production

# Backup all namespaces
velero backup create full-backup
```

### Restore from Backup

```bash
# Restore specific namespace
velero restore create <restore-name> \
  --from-backup <backup-name> \
  --include-namespaces vendure-production

# Restore all namespaces
velero restore create <restore-name> \
  --from-backup <backup-name>
```

### View Restores

```bash
# List all restores
velero restore get

# View restore details
velero restore describe <restore-name>
```

## S3 Versioning

S3 versioning is enabled to protect against:
- Accidental deletion
- Overwrites
- Corruption

### View Versions

```bash
# List all versions
aws s3api list-object-versions \
  --bucket vendure-velero-backups \
  --prefix backups/

# Restore specific version
aws s3api get-object \
  --bucket vendure-velero-backups \
  --key backups/<backup-name> \
  --version-id <version-id> \
  restored-backup.tar.gz
```

## Monitoring

### Check Backup Status

```bash
# View schedule
velero schedule get daily-backup

# View last backup
velero backup get | head -5

# Check S3 storage
aws s3 ls s3://vendure-velero-backups/backups/ --recursive --human-readable --summarize
```

### Alerts (Recommended)

Set up CloudWatch alarms for:
- Backup failures
- S3 storage usage
- Backup age (if no backup in 25 hours)

## Troubleshooting

### Backup Failing

1. **Check Velero logs:**
   ```bash
   kubectl logs -n velero -l component=velero --tail=100
   ```

2. **Check S3 permissions:**
   ```bash
   kubectl describe sa velero-server -n velero
   ```

3. **Verify S3 bucket:**
   ```bash
   aws s3 ls s3://vendure-velero-backups
   ```

### Restore Failing

1. **Check restore logs:**
   ```bash
   velero restore logs <restore-name>
   ```

2. **Verify backup exists:**
   ```bash
   velero backup describe <backup-name>
   ```

3. **Check namespace conflicts:**
   ```bash
   kubectl get all -n <namespace>
   ```

## Best Practices

1. **Test Restores Regularly**
   - Test restore to a test namespace monthly
   - Verify data integrity

2. **Monitor Backup Size**
   - Check S3 storage usage weekly
   - Adjust retention if needed

3. **Document Recovery Procedures**
   - Document restore steps
   - Test disaster recovery scenarios

4. **Keep Velero Updated**
   - Update Velero quarterly
   - Test backups after updates

## Cost Breakdown

### Monthly Costs (Example: 100GB backups)

- **S3 Standard Storage**: 100GB × $0.023 = $2.30/month
- **With Compression**: 30GB × $0.023 = $0.69/month
- **With Glacier (after 30 days)**: 30GB × $0.004 = $0.12/month
- **Total**: ~$0.50-2.30/month

### Optimization Tips

1. **Enable Compression**: Already enabled (saves 50-70%)
2. **Use Lifecycle Policies**: Already configured (saves 96% after 30 days)
3. **Selective Backup**: Only backup critical namespaces (already configured)
4. **Shorter Retention**: 7 days is optimal for cost

## Security

- **Encryption**: AES256 (enabled)
- **Access**: IRSA (IAM Roles for Service Accounts)
- **Public Access**: Blocked
- **Versioning**: Enabled (protects against deletion)

## References

- **Velero Docs**: https://velero.io/docs/
- **S3 Versioning**: https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html
- **EKS IRSA**: https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html


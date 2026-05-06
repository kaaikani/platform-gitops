# Log Retention Policy & Cost Management

## Overview

This document defines the log retention policies for Loki and Prometheus, including storage costs, growth monitoring, and optimization strategies.

## Current Retention Configuration

### Loki (Log Aggregation)

| Environment | Retention Period | Storage Size | Estimated Cost/Month |
|-------------|------------------|--------------|---------------------|
| **Test** | 7 days | 10 Gi | ~$0.80 |
| **Production** | 30 days | 50 Gi | ~$4.00 |

### Prometheus (Metrics)

| Environment | Retention Period | Storage Size | Estimated Cost/Month |
|-------------|------------------|--------------|---------------------|
| **Test** | 7 days | 20 Gi | ~$1.60 |
| **Production** | 30 days | 50 Gi | ~$4.00 |

### Total Storage Costs

| Environment | Total Storage | Monthly Cost |
|-------------|---------------|--------------|
| **Test** | 30 Gi | ~$2.40 |
| **Production** | 100 Gi | ~$8.00 |

## Storage Cost Breakdown

### AWS EBS gp3 Pricing (ap-south-1)
- **Storage**: $0.08 per GB/month
- **IOPS**: Included (3,000 baseline)
- **Throughput**: Included (125 MB/s baseline)

### Cost Calculation Examples

**Test Environment:**
```
Loki: 10 Gi × $0.08 = $0.80/month
Prometheus: 20 Gi × $0.08 = $1.60/month
Total: $2.40/month
```

**Production Environment:**
```
Loki: 50 Gi × $0.08 = $4.00/month
Prometheus: 50 Gi × $0.08 = $4.00/month
Total: $8.00/month
```

## Retention Policy Rationale

### Why 7 Days for Test?
- **Cost Savings**: Reduces storage costs by 75% vs 30 days
- **Sufficient for Debugging**: Most issues are found within 7 days
- **Fast Iteration**: Test environment doesn't need long-term history

### Why 30 Days for Production?
- **Compliance**: Many regulations require 30-day log retention
- **Incident Investigation**: Allows time to investigate security incidents
- **Trend Analysis**: Enough data for monthly reports
- **Cost Balance**: Reasonable cost ($8/month) for production value

## Storage Growth Monitoring

### Expected Growth Rates

**Loki (Logs):**
- **Test**: ~1.4 Gi/day (10 Gi ÷ 7 days)
- **Production**: ~1.7 Gi/day (50 Gi ÷ 30 days)

**Prometheus (Metrics):**
- **Test**: ~2.9 Gi/day (20 Gi ÷ 7 days)
- **Production**: ~1.7 Gi/day (50 Gi ÷ 30 days)

### Alert Thresholds

Set up alerts when storage exceeds:
- **Warning**: 80% of allocated storage
- **Critical**: 90% of allocated storage

## Cost Optimization Strategies

### 1. Adjust Retention Periods

**Option A: Reduce Production to 14 Days**
```
Savings: 50% reduction
New Cost: $4.00/month (vs $8.00/month)
Trade-off: Less historical data
```

**Option B: Reduce Production to 7 Days**
```
Savings: 75% reduction
New Cost: $2.00/month (vs $8.00/month)
Trade-off: Minimal historical data (may violate compliance)
```

### 2. Use S3 for Long-Term Storage

**Architecture:**
- Keep 7 days in Loki (hot storage)
- Archive older logs to S3 (cold storage)
- Cost: S3 Standard = $0.023/GB/month (71% cheaper)

**Example:**
```
Hot Storage (Loki): 10 Gi × $0.08 = $0.80/month
Cold Storage (S3): 40 Gi × $0.023 = $0.92/month
Total: $1.72/month (vs $4.00/month)
Savings: 57%
```

### 3. Filter Logs Before Storage

**Drop Debug Logs:**
```yaml
# In promtail config
pipeline_stages:
  - match:
      selector: '{level="debug"}'
      action: drop
```

**Estimated Savings**: 20-30% reduction in log volume

### 4. Compress Old Logs

Loki automatically compresses old chunks, but you can:
- Increase compression ratio
- Use more aggressive compression for older data

## Monitoring & Alerts

### Storage Usage Alerts

Create Prometheus alerts for storage growth:

```yaml
# Alert when Loki storage exceeds 80%
- alert: LokiStorageHigh
  expr: |
    (kubelet_volume_stats_used_bytes{persistentvolumeclaim="loki"}
     / kubelet_volume_stats_capacity_bytes{persistentvolumeclaim="loki"}) > 0.8
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Loki storage usage above 80%"
    description: "Loki PVC is {{ $value | humanizePercentage }} full"

# Alert when Prometheus storage exceeds 80%
- alert: PrometheusStorageHigh
  expr: |
    (prometheus_tsdb_storage_blocks_bytes
     / prometheus_tsdb_head_max_bytes) > 0.8
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Prometheus storage usage above 80%"
```

### Cost Monitoring

Track storage costs using Kubecost or AWS Cost Explorer:

```bash
# Check current storage usage
kubectl get pvc -n monitoring

# Check storage costs in AWS
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --filter file://storage-filter.json
```

## Retention Policy Enforcement

### Automatic Cleanup

Loki and Prometheus automatically delete old data based on retention settings:

**Loki:**
- `retention_period: 720h` (30 days)
- `retention_enabled: true`
- Runs via compactor component

**Prometheus:**
- `retention: 30d`
- Automatic cleanup on startup and periodically

### Manual Cleanup (Emergency)

If storage fills up unexpectedly:

```bash
# Check current usage
kubectl exec -n monitoring deployment/loki -- \
  du -sh /data/loki/chunks

# Force retention cleanup (Loki)
kubectl exec -n monitoring deployment/loki -- \
  loki -target=compactor -config.file=/etc/loki/loki.yaml

# Check Prometheus retention
kubectl exec -n monitoring deployment/prometheus -- \
  promtool tsdb analyze /prometheus
```

## Compliance Considerations

### Regulatory Requirements

| Regulation | Minimum Retention | Our Policy | Compliant? |
|------------|------------------|------------|------------|
| **GDPR** | Not specified (reasonable period) | 30 days | ✅ Yes |
| **PCI-DSS** | 1 year (for audit logs) | 30 days | ⚠️ May need extension |
| **SOC 2** | 90 days (recommended) | 30 days | ⚠️ May need extension |
| **HIPAA** | 6 years (for some logs) | 30 days | ❌ No (if applicable) |

### Recommendations

1. **For PCI-DSS Compliance**: Extend to 1 year for payment-related logs
2. **For SOC 2**: Consider 90-day retention
3. **For HIPAA**: Use external log archive (S3) with 6-year retention

## Best Practices

### 1. Regular Review
- **Monthly**: Review storage growth trends
- **Quarterly**: Review retention policies
- **Annually**: Review compliance requirements

### 2. Cost Optimization
- Monitor actual usage vs allocated
- Right-size storage based on growth
- Consider S3 for long-term archive

### 3. Alerting
- Set up storage usage alerts
- Monitor cost trends
- Alert on unexpected growth

### 4. Documentation
- Document retention decisions
- Track compliance requirements
- Maintain cost tracking

## Configuration Files

### Test Environment
- **Loki**: `helm/environments/test/loki-values.yaml`
- **Prometheus**: `helm/environments/test/monitoring-values.yaml`

### Production Environment
- **Loki**: `helm/environments/production/loki-values.yaml` (NEW)
- **Prometheus**: `helm/environments/production/monitoring-values.yaml`

## Cost Tracking

### Monthly Cost Report Template

```markdown
## Storage Cost Report - [Month Year]

### Test Environment
- Loki: [X] Gi × $0.08 = $[X.XX]
- Prometheus: [X] Gi × $0.08 = $[X.XX]
- **Total**: $[X.XX]

### Production Environment
- Loki: [X] Gi × $0.08 = $[X.XX]
- Prometheus: [X] Gi × $0.08 = $[X.XX]
- **Total**: $[X.XX]

### Growth Trends
- Loki growth: [X]% month-over-month
- Prometheus growth: [X]% month-over-month

### Recommendations
- [Action items based on trends]
```

## References

- [Loki Retention Documentation](https://grafana.com/docs/loki/latest/operations/storage/retention/)
- [Prometheus Retention Documentation](https://prometheus.io/docs/prometheus/latest/storage/)
- [AWS EBS Pricing](https://aws.amazon.com/ebs/pricing/)
- [AWS S3 Pricing](https://aws.amazon.com/s3/pricing/)


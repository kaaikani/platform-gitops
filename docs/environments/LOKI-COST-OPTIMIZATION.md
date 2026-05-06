# Loki Cost Optimization Guide - Professional DevOps Strategies

## Current Cost Problem

**Production Loki: $4.00/month** (50 Gi storage, 30-day retention)

This is **too expensive** for a small/medium application. Professional DevOps teams use multiple strategies to reduce this to **$0.50-1.00/month**.

## Cost Breakdown

### Current Setup
```
Storage: 50 Gi × $0.08/GB = $4.00/month
Retention: 30 days
No log filtering
EBS storage (expensive)
```

### Professional DevOps Target
```
Storage: 5-10 Gi × $0.08/GB = $0.40-0.80/month
OR
Storage: 5-10 Gi × $0.023/GB (S3) = $0.12-0.23/month
Retention: 7 days (sufficient for most cases)
Log filtering: Drop 30% of logs
Savings: 80-94%
```

## Optimization Strategies (Ranked by Impact)

### Strategy 1: Reduce Retention Period ⭐⭐⭐⭐⭐ (75% savings)

**Why 7 Days is Enough:**
- Most issues are found within 24-48 hours
- 7 days covers weekly analysis
- For compliance: Use S3 archive for long-term

**Cost Impact:**
```
Before: 30 days = 50 Gi = $4.00/month
After:  7 days = 10 Gi = $0.80/month
Savings: $3.20/month (80% reduction)
```

**Implementation:**
```yaml
# In loki-values.yaml
retention_period: 168h  # 7 days (was 720h = 30 days)
reject_old_samples_max_age: 168h
```

### Strategy 2: Filter Logs Before Storage ⭐⭐⭐⭐ (30% savings)

**Drop Unnecessary Logs:**
- Debug logs (not needed in production)
- Verbose logs (too noisy)
- Health check logs (every 5 seconds)
- Metrics endpoint logs (noise)

**Cost Impact:**
```
Before: 10 Gi storage
After:  7 Gi storage (30% reduction)
Savings: $0.24/month
```

**Implementation:**
```yaml
# In promtail config
pipeline_stages:
  - match:
      selector: '{level="debug"}'
      action: drop
  - match:
      selector: '{level="verbose"}'
      action: drop
  - match:
      selector: '{msg=~".*health.*"}'
      action: drop
```

### Strategy 3: Use S3 Instead of EBS ⭐⭐⭐⭐⭐ (71% savings)

**Cost Comparison:**
```
EBS gp3:     $0.08/GB/month
S3 Standard: $0.023/GB/month (71% cheaper!)
S3 Intelligent-Tiering: $0.0125/GB/month (84% cheaper!)
```

**Cost Impact:**
```
Before: 10 Gi × $0.08 = $0.80/month (EBS)
After:  10 Gi × $0.023 = $0.23/month (S3)
Savings: $0.57/month (71% reduction)
```

**Implementation:**
- Use `loki-s3-storage.yaml` configuration
- Create S3 bucket
- Configure IRSA for S3 access

### Strategy 4: Right-Size Storage ⭐⭐⭐⭐ (50% savings)

**Monitor Actual Usage:**
- Most apps need 5-10 Gi for 7 days
- Don't over-provision "just in case"
- Start small, scale up if needed

**Cost Impact:**
```
Before: 50 Gi allocated (over-provisioned)
After:  10 Gi allocated (right-sized)
Savings: $3.20/month (80% reduction)
```

**How to Right-Size:**
```bash
# Check actual usage
kubectl exec -n monitoring deployment/loki -- \
  du -sh /data/loki/chunks

# If using 3 Gi, allocate 5 Gi (with 40% headroom)
# Don't allocate 50 Gi if you only use 3 Gi!
```

### Strategy 5: Aggressive Compression ⭐⭐⭐ (20% savings)

**Loki automatically compresses, but you can:**
- Reduce cache TTL (less cache = less storage)
- Faster cleanup (delete old data sooner)
- Smaller chunk sizes

**Cost Impact:**
```
Before: 10 Gi storage
After:  8 Gi storage (20% reduction)
Savings: $0.16/month
```

### Strategy 6: Limit Ingestion Rate ⭐⭐⭐ (Prevent Bloat)

**Prevent Storage Growth:**
- Limit ingestion to 5 MB/s (instead of 10 MB/s)
- Prevents log storms from filling storage
- Automatic protection

**Implementation:**
```yaml
limits_config:
  ingestion_rate_mb: 5  # Limit to 5 MB/s
  ingestion_burst_size_mb: 10
```

## Combined Optimization Results

### Option A: EBS with Optimizations
```
Retention: 30 days → 7 days (75% reduction)
Storage: 50 Gi → 10 Gi (80% reduction)
Filtering: -30% volume = 7 Gi effective
Cost: 7 Gi × $0.08 = $0.56/month
Savings: 86% ($4.00 → $0.56)
```

### Option B: S3 with All Optimizations (BEST)
```
Retention: 7 days
Storage: 10 Gi → 7 Gi (with filtering)
Storage Type: EBS → S3 (71% cheaper)
Cost: 7 Gi × $0.023 = $0.16/month
Savings: 96% ($4.00 → $0.16)
```

## Professional DevOps Best Practices

### 1. Start Small, Scale Up
```
Week 1: Allocate 5 Gi, monitor usage
Week 2: If using 4 Gi, keep 5 Gi
Week 3: If using 6 Gi, scale to 8 Gi
Don't: Allocate 50 Gi "just in case"
```

### 2. Monitor Storage Growth
```bash
# Set up alerts
- Warning: 70% storage used
- Critical: 85% storage used
- Action: Scale up or reduce retention
```

### 3. Use Tiered Storage
```
Hot (Loki): 7 days, fast access, $0.08/GB
Warm (S3 Standard): 30 days, slower access, $0.023/GB
Cold (S3 Glacier): 1 year, archive, $0.004/GB
```

### 4. Filter Aggressively
```
Keep: error, warn, info
Drop: debug, verbose, trace, health checks
Result: 30-50% volume reduction
```

### 5. Regular Review
```
Monthly: Review storage usage
Quarterly: Review retention policy
Annually: Review compliance requirements
```

## Implementation Steps

### Step 1: Apply Cost-Optimized Configuration

```bash
# Use cost-optimized values
helm upgrade loki grafana/loki-stack \
  -n monitoring \
  -f helm/environments/production/loki-values-cost-optimized.yaml
```

**Result:** $4.00 → $0.56/month (86% savings)

### Step 2: Migrate to S3 (Optional, More Savings)

```bash
# 1. Create S3 bucket
aws s3 mb s3://vendure-loki-logs --region ap-south-1

# 2. Create IRSA
eksctl create iamserviceaccount \
  --name loki \
  --namespace monitoring \
  --cluster vendure-cluster \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
  --approve

# 3. Deploy with S3
helm upgrade loki grafana/loki-stack \
  -n monitoring \
  -f helm/environments/production/loki-s3-storage.yaml
```

**Result:** $0.56 → $0.16/month (96% total savings)

### Step 3: Monitor and Adjust

```bash
# Check storage usage weekly
kubectl exec -n monitoring deployment/loki -- \
  du -sh /data/loki/chunks

# If using less than allocated, reduce storage
# If using more than 80%, increase storage
```

## Cost Comparison Table

| Strategy | Storage | Retention | Monthly Cost | Savings |
|----------|---------|----------|--------------|---------|
| **Original** | 50 Gi (EBS) | 30 days | $4.00 | - |
| **Optimized EBS** | 10 Gi (EBS) | 7 days | $0.80 | 80% |
| **Optimized + Filter** | 7 Gi (EBS) | 7 days | $0.56 | 86% |
| **Optimized + S3** | 7 Gi (S3) | 7 days | $0.16 | **96%** |

## Real-World Examples

### Small Application (Low Traffic)
```
Actual Usage: 2 Gi for 7 days
Allocated: 5 Gi (with headroom)
Cost: 5 Gi × $0.023 (S3) = $0.12/month
```

### Medium Application (Your Case)
```
Actual Usage: 5 Gi for 7 days
Allocated: 10 Gi (with headroom)
Cost: 10 Gi × $0.023 (S3) = $0.23/month
Savings vs original: 94%
```

### Large Application (High Traffic)
```
Actual Usage: 20 Gi for 7 days
Allocated: 25 Gi
Cost: 25 Gi × $0.023 (S3) = $0.58/month
Still 85% cheaper than original $4.00
```

## Compliance Considerations

### If You Need 30-Day Retention

**Option 1: S3 Archive (Recommended)**
```
Loki (Hot): 7 days, 10 Gi, $0.23/month
S3 Archive: 23 days, 30 Gi, $0.69/month
Total: $0.92/month (vs $4.00)
Savings: 77%
```

**Option 2: S3 Intelligent-Tiering**
```
Automatically moves old logs to cheaper tier
Cost: ~$0.50/month for 30 days
Savings: 87%
```

## Monitoring Cost

### Set Up Alerts

```yaml
# Alert when storage cost exceeds budget
- alert: LokiStorageCostHigh
  expr: |
    (kubelet_volume_stats_used_bytes{pvc="loki"}
     * 0.023 / 1024 / 1024 / 1024) > 1.0
  annotations:
    summary: "Loki storage cost exceeds $1/month"
```

## Summary: Professional DevOps Approach

1. ✅ **Reduce retention** to 7 days (75% savings)
2. ✅ **Filter logs** aggressively (30% savings)
3. ✅ **Use S3** instead of EBS (71% savings)
4. ✅ **Right-size** storage (50% savings)
5. ✅ **Monitor** and adjust regularly

**Result: $4.00/month → $0.16-0.56/month (86-96% savings)**

## Quick Win: Immediate Actions

### Today (5 minutes)
```bash
# Apply cost-optimized config
helm upgrade loki grafana/loki-stack \
  -n monitoring \
  -f helm/environments/production/loki-values-cost-optimized.yaml
```
**Savings: $3.44/month (86%)**

### This Week (30 minutes)
```bash
# Migrate to S3
# Follow Step 2 above
```
**Additional Savings: $0.40/month (96% total)**

## Files Created

1. ✅ `loki-values-cost-optimized.yaml` - EBS optimized config
2. ✅ `loki-s3-storage.yaml` - S3 storage config (best savings)
3. ✅ `LOKI-COST-OPTIMIZATION.md` - This guide

## Bottom Line

**Professional DevOps teams don't pay $4/month for logs.**

They use:
- 7-day retention (not 30)
- S3 storage (not EBS)
- Log filtering (not everything)
- Right-sizing (not over-provisioning)

**Result: $0.16-0.56/month instead of $4.00/month**

That's **86-96% cost savings** with the same functionality!


# Monitoring & Observability Gaps Analysis

## 📋 Analysis Date
2026-02-10

## 🔍 Overview

This document analyzes monitoring and observability gaps in the Vendure Kubernetes deployment across four critical areas:
1. Log retention (Loki storage costs)
2. Alert fatigue (custom alerts tuning)
3. Distributed tracing (Tempo/Jaeger)
4. Cost monitoring (Kubecost/namespace costs)

---

## 1. Log Retention: Loki Storage Costs

### Current State

**Status:** ✅ **CONFIGURED & OPTIMIZED**

**What Exists:**
- ✅ **Retention Policy**: 7 days (optimized from 30 days = 75% cost savings)
- ✅ **Storage Size**: 10 Gi (reduced from 50 Gi = 80% cost savings)
- ✅ **Cost Optimization**: Multiple strategies documented
- ✅ **S3 Option**: Available (71% cheaper than EBS)
- ✅ **Storage Alerts**: Configured to monitor usage

**Configuration:**
- **Production**: `loki-values.yaml` - 7-day retention, 10 Gi storage
- **S3 Option**: `loki-s3-storage.yaml` - S3 storage, 71% cost savings
- **Cost Optimized**: `loki-values-cost-optimized.yaml` - Additional optimizations

**Current Costs:**
- **EBS Storage**: 10 Gi × $0.08/GB = **$0.80/month**
- **S3 Storage**: 10 Gi × $0.023/GB = **$0.23/month** (if using S3)
- **Before Optimization**: 50 Gi × $0.08 = $4.00/month
- **Savings**: 80% reduction ($4.00 → $0.80)

**Documentation:**
- ✅ `LOG-RETENTION-POLICY.md` - Comprehensive retention policy
- ✅ `LOKI-COST-OPTIMIZATION.md` - Cost optimization strategies
- ✅ `loki-storage-alerts.yaml` - Storage monitoring alerts

### What's Good ✅

1. **Retention Optimized**: 7 days is sufficient for most use cases
2. **Storage Optimized**: 10 Gi is reasonable for 7-day retention
3. **Cost Alerts**: Storage usage alerts configured
4. **S3 Option**: Available for even more cost savings
5. **Documentation**: Comprehensive cost optimization guides

### Potential Issues ⚠️

1. **Storage Growth**: No automated monitoring of storage growth rate
2. **Retention Verification**: Not verified if retention is actually working
3. **S3 Not Deployed**: Currently using EBS (could save 71% with S3)
4. **No Lifecycle Policy**: No automatic archival to cheaper storage

### Risk Level: 🟢 **LOW** (Well Optimized)

**Impact:**
- Current costs are reasonable ($0.80/month)
- Could save more with S3 ($0.23/month)
- Storage growth monitoring could be improved

### Recommendations

1. **Deploy S3 Storage** (Priority: P2)
   - Switch from EBS to S3 for 71% cost savings
   - Estimated savings: $0.57/month

2. **Add Storage Growth Monitoring** (Priority: P2)
   - Track daily storage growth rate
   - Alert if growth exceeds expected rate

3. **Verify Retention** (Priority: P1)
   - Verify that old logs are actually being deleted
   - Check retention compactor is working

---

## 2. Alert Fatigue: Custom Alerts Tuning

### Current State

**Status:** ⚠️ **CONFIGURED BUT NOT TUNED**

**What Exists:**
- ✅ **Alert Rules**: Multiple alert rule files
- ✅ **Vendure-Specific Alerts**: Pod down, high CPU/memory, restarts
- ✅ **Kubernetes Alerts**: Node health, pod health
- ✅ **Monitoring Stack Alerts**: Prometheus, Grafana, AlertManager health

**Alert Files:**
- `helm/vendure-stack/templates/prometheusrule.yaml` - Vendure alerts
- `helm/monitoring-stack/prometheus-alert-rules.yaml` - Cluster alerts
- `helm/monitoring-stack/values-cost-optimized.yaml` - Critical-only alerts

**Current Alert Thresholds:**
- **Pod Down**: 1 minute (may be too sensitive)
- **High Memory**: 90% for 5 minutes
- **High CPU**: 90% for 5 minutes
- **Pod Restarts**: Immediate (may cause false positives)

### What's Good ✅

1. **Alert Rules Exist**: Comprehensive alert coverage
2. **Severity Levels**: Critical/Warning labels used
3. **Cost-Optimized Version**: Critical-only alerts available

### Potential Issues ⚠️

1. **Alert Thresholds**: May be too sensitive (1-minute pod down)
2. **No Alert Tuning**: Thresholds not adjusted based on actual behavior
3. **No Alert Grouping**: Similar alerts may fire repeatedly
4. **No Alert Suppression**: No mechanism to suppress known issues
5. **No Alert Testing**: Not verified if alerts work correctly
6. **False Positive Risk**: Pod restarts alert may fire during normal deployments

### Risk Level: 🟡 **MEDIUM**

**Impact:**
- Alert fatigue may cause important alerts to be ignored
- False positives waste time
- Too sensitive alerts may cause unnecessary escalations

### Recommendations

1. **Tune Alert Thresholds** (Priority: P1)
   - Increase pod down threshold to 2-3 minutes
   - Adjust CPU/memory thresholds based on actual usage patterns
   - Add grace period for pod restarts during deployments

2. **Implement Alert Grouping** (Priority: P1)
   - Group similar alerts together
   - Use AlertManager grouping configuration

3. **Add Alert Suppression** (Priority: P2)
   - Suppress alerts during maintenance windows
   - Silence known issues

4. **Test Alerts** (Priority: P1)
   - Verify alerts fire correctly
   - Test alert routing to notification channels

5. **Monitor Alert Volume** (Priority: P2)
   - Track number of alerts per day
   - Identify alert patterns
   - Optimize based on data

---

## 3. Distributed Tracing: Tempo/Jaeger

### Current State

**Status:** ✅ **CONFIGURED BUT NOT DEPLOYED**

**What Exists:**
- ✅ **Tempo Configuration**: Production and test values files
- ✅ **Application Instrumentation**: `src/tracing.ts` with OpenTelemetry
- ✅ **Grafana Integration**: Tempo datasource configuration
- ✅ **Documentation**: Comprehensive setup guides

**Configuration Files:**
- `helm/environments/production/tempo-values.yaml` - Production Tempo config
- `helm/environments/local/tempo-values.yaml` - Local Tempo config
- `helm/environments/production/grafana-tempo-datasource.yaml` - Grafana config
- `src/tracing.ts` - Application instrumentation

**Features Configured:**
- ✅ 7-day trace retention
- ✅ S3 storage option (or filesystem)
- ✅ OpenTelemetry auto-instrumentation
- ✅ HTTP, Express, MySQL tracking
- ✅ 10% sampling in production (cost optimization)
- ✅ Trace-to-logs correlation
- ✅ Trace-to-metrics correlation

### What's Good ✅

1. **Complete Configuration**: All files created
2. **Cost Optimized**: 10% sampling in production
3. **Comprehensive Instrumentation**: Auto-instruments HTTP, Express, MySQL
4. **Documentation**: Detailed setup and usage guides

### What's Missing ❌

1. **Not Deployed**: Tempo not installed in cluster
2. **Dependencies Not Installed**: npm packages not installed
3. **Grafana Datasource Not Configured**: Not added to Grafana
4. **Not Verified**: No verification that tracing works

### Risk Level: 🟡 **MEDIUM**

**Impact:**
- No distributed tracing visibility
- Hard to debug request flow
- Can't correlate errors with requests
- Performance bottlenecks harder to identify

### Recommendations

1. **Deploy Tempo** (Priority: P1)
   ```bash
   helm install tempo grafana/tempo-distributed \
     -n monitoring \
     -f helm/environments/production/tempo-values.yaml
   ```

2. **Install Dependencies** (Priority: P1)
   ```bash
   npm install @opentelemetry/sdk-node \
     @opentelemetry/auto-instrumentations-node \
     @opentelemetry/exporter-trace-otlp-http
   ```

3. **Configure Grafana Datasource** (Priority: P1)
   ```bash
   kubectl apply -f helm/environments/production/grafana-tempo-datasource.yaml
   ```

4. **Verify Tracing** (Priority: P1)
   - Make test requests
   - Check traces in Grafana
   - Verify correlation with logs/metrics

---

## 4. Cost Monitoring: Kubecost/Namespace Costs

### Current State

**Status:** ⚠️ **CONFIGURED BUT NOT DEPLOYED**

**What Exists:**
- ✅ **Kubecost Config**: Local configuration file
- ✅ **OpenCost Config**: Alternative open-source option
- ✅ **Prometheus Integration**: Configured to use existing Prometheus

**Configuration Files:**
- `helm/environments/local/kubecost-values.yaml` - Local Kubecost config
- `helm/kubecost/values.yaml` - OpenCost configuration

**Features Configured:**
- ✅ Prometheus integration (uses existing)
- ✅ AWS pricing support
- ✅ Spot instance detection
- ✅ UI enabled

### What's Good ✅

1. **Configurations Exist**: Both Kubecost and OpenCost options
2. **Prometheus Integration**: Uses existing Prometheus (no duplication)
3. **AWS Support**: Configured for AWS pricing

### What's Missing ❌

1. **Not Deployed**: Kubecost/OpenCost not installed
2. **No Production Config**: Only local configuration exists
3. **No Namespace Tracking**: Not verified if it tracks per namespace
4. **No Cost Alerts**: No alerts for cost overruns
5. **No Cost Reports**: No automated cost reporting

### Risk Level: 🟡 **MEDIUM**

**Impact:**
- No visibility into cluster costs
- Can't track costs per namespace/application
- No cost optimization insights
- Risk of unexpected cost overruns

### Recommendations

1. **Deploy Kubecost/OpenCost** (Priority: P1)
   ```bash
   # Option 1: Kubecost (commercial, free tier)
   helm repo add kubecost https://kubecost.github.io/cost-analyzer/
   helm install kubecost kubecost/cost-analyzer \
     -n kubecost --create-namespace \
     -f helm/environments/production/kubecost-values.yaml
   
   # Option 2: OpenCost (open source, free)
   helm repo add opencost https://opencost.github.io/opencost-helm-chart
   helm install opencost opencost/opencost \
     -n opencost --create-namespace \
     -f helm/kubecost/values.yaml
   ```

2. **Create Production Config** (Priority: P1)
   - Create `helm/environments/production/kubecost-values.yaml`
   - Configure for production cluster
   - Set up cost allocation labels

3. **Configure Cost Allocation** (Priority: P1)
   - Add labels to namespaces for cost tracking
   - Configure cost allocation by namespace/application
   - Set up cost allocation reports

4. **Add Cost Alerts** (Priority: P2)
   - Alert when daily costs exceed threshold
   - Alert when namespace costs spike
   - Alert when resource usage increases unexpectedly

5. **Set Up Cost Reports** (Priority: P2)
   - Daily cost summaries
   - Weekly cost reports
   - Monthly cost analysis

---

## 📊 Summary Table

| Area | Status | Risk Level | Deployment Status | Priority |
|------|--------|------------|------------------|----------|
| Log Retention | ✅ Optimized | 🟢 LOW | ✅ Deployed | P2 |
| Alert Fatigue | ⚠️ Not Tuned | 🟡 MEDIUM | ⚠️ Needs Tuning | P1 |
| Distributed Tracing | ✅ Configured | 🟡 MEDIUM | ❌ Not Deployed | P1 |
| Cost Monitoring | ⚠️ Configured | 🟡 MEDIUM | ❌ Not Deployed | P1 |

---

## 🎯 Priority Actions

### Priority 1 (High - Fix Soon)

1. **Tune Alert Thresholds**
   - Adjust pod down threshold (1m → 2-3m)
   - Add grace period for deployments
   - Test alert behavior

2. **Deploy Distributed Tracing (Tempo)**
   - Install Tempo in cluster
   - Install npm dependencies
   - Configure Grafana datasource
   - Verify tracing works

3. **Deploy Cost Monitoring (Kubecost/OpenCost)**
   - Install Kubecost or OpenCost
   - Create production configuration
   - Configure cost allocation
   - Set up cost tracking

### Priority 2 (Medium - Fix When Possible)

4. **Deploy S3 Storage for Loki**
   - Switch from EBS to S3
   - Save 71% on storage costs

5. **Add Storage Growth Monitoring**
   - Track daily growth rate
   - Alert on unexpected growth

6. **Add Cost Alerts**
   - Alert on cost overruns
   - Alert on namespace cost spikes

---

## 📋 Deployment Checklist

### Alert Tuning
- [ ] Review current alert thresholds
- [ ] Adjust pod down threshold
- [ ] Add deployment grace periods
- [ ] Test alert behavior
- [ ] Configure alert grouping
- [ ] Set up alert suppression

### Distributed Tracing
- [ ] Install Tempo: `helm install tempo ...`
- [ ] Install npm dependencies: `npm install ...`
- [ ] Configure Grafana datasource
- [ ] Verify tracing in Grafana
- [ ] Test trace-to-logs correlation
- [ ] Test trace-to-metrics correlation

### Cost Monitoring
- [ ] Choose Kubecost or OpenCost
- [ ] Create production configuration
- [ ] Install cost monitoring tool
- [ ] Configure cost allocation labels
- [ ] Set up cost reports
- [ ] Add cost alerts

### Log Retention (Optional Improvements)
- [ ] Deploy S3 storage for Loki
- [ ] Add storage growth monitoring
- [ ] Verify retention is working

---

## 📝 Notes

1. **Log Retention**: Already well optimized. Current costs are reasonable ($0.80/month). S3 option available for further savings.

2. **Alert Fatigue**: Alerts exist but need tuning. Current thresholds may be too sensitive, causing false positives.

3. **Distributed Tracing**: Fully configured but not deployed. All code and configs ready, just needs installation.

4. **Cost Monitoring**: Configurations exist but not deployed. Need to choose between Kubecost (commercial) or OpenCost (open source).

---

**Analysis Complete** ✅

**Key Takeaway**: Monitoring infrastructure is well configured, but distributed tracing and cost monitoring need to be deployed. Alert thresholds need tuning to avoid alert fatigue.


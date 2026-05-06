# Network Policy Security Configuration

## Overview

This Helm chart implements **default-deny** network policies for enhanced security. All pods are denied network access by default, and specific policies allow only necessary traffic.

## Security Model

### Default-Deny Policy
- **File**: `networkpolicy-default-deny.yaml`
- **Applies to**: ALL pods in the namespace
- **Effect**: Denies all ingress and egress traffic by default
- **Purpose**: Ensures pods without explicit NetworkPolicy cannot communicate

### Allow Policies
- **Vendure Pods**: Allows specific traffic to/from Vendure application
- **MySQL Pods**: Only allows Vendure to connect (if in-cluster)
- **Redis Pods**: Only allows Vendure to connect (if in-cluster)

## Traffic Rules

### Ingress (Traffic TO Vendure)

| Source | Ports | Purpose |
|--------|-------|---------|
| Same namespace | 80, 3002 | ALB traffic, pod-to-pod communication |
| kube-system namespace | 80, 3002 | ALB controller routing |
| monitoring namespace (Prometheus) | 80 | Metrics scraping |

### Egress (Traffic FROM Vendure)

| Destination | Ports | Purpose |
|-------------|-------|---------|
| kube-system (CoreDNS) | 53 (UDP/TCP) | DNS resolution |
| External MySQL (RDS) | 3306 | Database connections |
| External Redis | 6379 | Cache connections |
| External HTTPS | 443 | AWS services (S3, Secrets Manager) |
| External HTTP | 80 | Health checks, external APIs |
| External SMTP | 25, 587, 465 | Email sending |
| monitoring (Prometheus) | 9090 | Metrics push (if enabled) |

## Security Improvements

### ✅ What's Secure Now

1. **Default-Deny**: All pods blocked by default
2. **Namespace Isolation**: Only allows traffic from specific namespaces
3. **Port Restrictions**: Only necessary ports are open
4. **Pod Selectors**: Specific pod labels required for access

### ⚠️ Known Limitations

1. **ALB Traffic**: Must allow from namespace (ALB uses node IPs, not pod IPs)
   - **Mitigation**: Still more secure than allowing all namespaces
   - **Future**: Can restrict to VPC CIDR if known

2. **External Services**: Egress to external services uses empty selector
   - **Reason**: RDS, Redis Cloud, AWS services are external
   - **Mitigation**: Ports are restricted (3306, 6379, 443, 80)
   - **Future**: Can restrict to specific IP ranges if known

3. **SMTP**: Allows all SMTP ports
   - **Reason**: Different email providers use different ports
   - **Future**: Restrict to specific SMTP server IPs if known

## Testing

### Run Network Policy Tests

```bash
# Test network policies
./helm/vendure-stack/templates/networkpolicy-test.sh vendure-production

# Or manually test
kubectl run test-pod --image=busybox -n vendure-production --rm -it -- sh
# Try to connect to Vendure (should fail)
wget -O- http://vendure-service:80
```

### Verify Legitimate Traffic

```bash
# From Vendure pod, test database
kubectl exec -n vendure-production deployment/vendure -- \
  nc -zv <rds-endpoint> 3306

# Test Redis
kubectl exec -n vendure-production deployment/vendure -- \
  nc -zv <redis-endpoint> 6379

# Test HTTPS
kubectl exec -n vendure-production deployment/vendure -- \
  wget -q --spider https://s3.ap-south-1.amazonaws.com
```

## Deployment

### Enable Network Policies

```yaml
# In vendure-values.yaml
networkPolicies:
  enabled: true
```

### Apply Policies

```bash
# Deploy with network policies
helm upgrade vendure ./helm/vendure-stack \
  -n vendure-production \
  -f helm/environments/production/vendure-values.yaml
```

### Verify Policies Applied

```bash
# Check default-deny policy
kubectl get networkpolicy default-deny-all -n vendure-production

# Check all network policies
kubectl get networkpolicy -n vendure-production

# View policy details
kubectl describe networkpolicy default-deny-all -n vendure-production
```

## Troubleshooting

### Issue: Application can't connect to database

**Check**:
```bash
# Verify network policy allows egress to port 3306
kubectl describe networkpolicy -n vendure-production | grep -A 5 "3306"

# Test connection from pod
kubectl exec -n vendure-production deployment/vendure -- \
  nc -zv <rds-endpoint> 3306
```

**Fix**: Ensure external database egress rule is present in network policy

### Issue: Prometheus can't scrape metrics

**Check**:
```bash
# Verify Prometheus can reach Vendure
kubectl exec -n monitoring deployment/prometheus -- \
  wget -O- http://vendure-service.vendure-production:80/metrics
```

**Fix**: Ensure monitoring namespace ingress rule is present

### Issue: ALB can't reach pods

**Check**:
```bash
# Verify ALB ingress controller is running
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# Check network policy allows from kube-system
kubectl describe networkpolicy -n vendure-production | grep kube-system
```

**Fix**: Ensure kube-system namespace ingress rule is present

## Future Enhancements

1. **IP Block Restrictions**: Restrict egress to specific IP ranges for RDS, Redis
2. **VPC CIDR**: Use VPC CIDR for ALB traffic instead of namespace selector
3. **SMTP IPs**: Restrict SMTP to specific email provider IPs
4. **AWS IP Ranges**: Restrict HTTPS to AWS service IP ranges only

## References

- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [AWS EKS Network Policies](https://docs.aws.amazon.com/eks/latest/userguide/network-policies.html)
- [Network Policy Best Practices](https://kubernetes.io/docs/concepts/services-networking/network-policies/#network-policy-resources)


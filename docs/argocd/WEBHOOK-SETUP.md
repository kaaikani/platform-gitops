# ArgoCD GitHub Webhook Setup

## Problem
ArgoCD uses polling (3-minute delay) by default. Webhooks enable instant sync when you push to GitHub.

## Solution: Configure GitHub Webhook

### Step 1: Get ArgoCD Webhook URL

```bash
# Get ArgoCD server URL (if using ingress)
ARGOCD_URL="https://argocd.yourdomain.com"

# Or if using port-forward
ARGOCD_URL="https://localhost:8080"

# Webhook endpoint
WEBHOOK_URL="${ARGOCD_URL}/api/webhook"
```

### Step 2: Create ArgoCD Webhook Secret

```bash
# Generate a secure webhook secret
WEBHOOK_SECRET=$(openssl rand -hex 32)

# Save it to ArgoCD (if using basic webhook)
kubectl create secret generic argocd-webhook-secret \
  --from-literal=secret=$WEBHOOK_SECRET \
  -n argocd

# Or configure in argocd-secret
kubectl patch secret argocd-secret -n argocd \
  --type merge \
  -p "{\"data\":{\"webhook.github.secret\":\"$(echo -n $WEBHOOK_SECRET | base64)\"}}"

echo "Webhook Secret: $WEBHOOK_SECRET"
# SAVE THIS SECRET - you'll need it for GitHub
```

### Step 3: Configure GitHub Webhook

1. Go to your GitHub repository: https://github.com/kaaikani/devops_testing_repo
2. Navigate to **Settings → Webhooks → Add webhook**
3. Configure:
   - **Payload URL**: `https://argocd.yourdomain.com/api/webhook`
   - **Content type**: `application/json`
   - **Secret**: (paste the WEBHOOK_SECRET from above)
   - **Which events**: Select "Just the push event"
   - **Active**: ✅ Check this box
4. Click **Add webhook**

### Step 4: Test the Webhook

```bash
# Make a small change and push to main branch
echo "# Test webhook" >> README.md
git add README.md
git commit -m "test: trigger ArgoCD webhook"
git push origin main

# ArgoCD should sync within 5-10 seconds
kubectl get applications -n argocd -w
```

## Alternative: Reduce Polling Interval

If you can't configure webhooks, reduce the polling interval:

```bash
# Edit argocd-cm ConfigMap
kubectl edit configmap argocd-cm -n argocd
```

Add this to the data section:

```yaml
data:
  timeout.reconciliation: 30s  # Default is 3m (180s)
```

Then restart ArgoCD:

```bash
kubectl rollout restart deployment argocd-repo-server -n argocd
kubectl rollout restart deployment argocd-application-controller -n argocd
```

## Verification

### Check if webhook is working:

```bash
# Check ArgoCD server logs for webhook events
kubectl logs -n argocd deployment/argocd-server --tail=100 | grep webhook

# Check application sync status
argocd app get vendure-test --refresh

# Force refresh to test
argocd app get vendure-test --hard-refresh
```

## Troubleshooting

### Webhook not triggering:

1. **Check GitHub webhook delivery**:
   - Go to GitHub → Settings → Webhooks
   - Click on your webhook
   - Check "Recent Deliveries" tab
   - Look for 200 OK response

2. **Check ArgoCD logs**:
   ```bash
   kubectl logs -n argocd deployment/argocd-server -f | grep -i webhook
   ```

3. **Verify ArgoCD URL is accessible** from GitHub:
   - ArgoCD must be publicly accessible (or use GitHub Enterprise with internal webhooks)
   - Test: `curl -X POST https://argocd.yourdomain.com/api/webhook`

### Common Issues:

- **403 Forbidden**: Webhook secret mismatch
- **404 Not Found**: Wrong webhook URL
- **Timeout**: ArgoCD not publicly accessible
- **SSL Error**: Certificate issues

## References

- [ArgoCD Webhook Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/webhook/)
- [GitHub Webhooks Guide](https://docs.github.com/en/webhooks)

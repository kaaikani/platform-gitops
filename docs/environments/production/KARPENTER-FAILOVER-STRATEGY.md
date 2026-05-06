# Karpenter Failover Strategy & Fallback Node Group

**Severity:** Low–Medium  
**Purpose:** Ensure application workloads can still schedule when Karpenter is unavailable (controller crash, AWS API throttling, or controller namespace issues).

---

## 1. Risks When Relying Only on Karpenter

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Karpenter controller crashes** | No new nodes provisioned; existing nodes keep running. New pods (scale-up, reschedule, new rollout) may stay Pending. | Fallback managed node group with same labels (`node-group=app`) so pending pods can schedule. Restart Karpenter. |
| **AWS API throttling** | Karpenter backs off; provisioning slows or fails. | Fallback node group absorbs baseline capacity; Karpenter only needed for burst. Retries and backoff are built into Karpenter. |
| **Karpenter namespace/Helm removed** | No auto-provisioning until reinstalled. | Fallback node group sized to run minimum production replicas (e.g. Vendure min replicas + worker). |
| **EC2 quota or capacity issues** | Karpenter cannot launch instances in a given AZ or type. | Multi-AZ fallback node group; document which instance types and AZs the fallback uses. |

---

## 2. Fallback Node Group Capacity Planning

**Recommendation:** Keep at least one **managed node group** (EKS `create-nodegroup`) that:

1. **Uses the same node labels** as Karpenter-provisioned app nodes so workloads can schedule there:
   - `node-group: app` (required — used by Vendure, Storefront, Southmithai `nodeSelector`)
   - Optionally: `node-type: on-demand`, `workload: vendure` if you want consistency with Karpenter node labels
2. **Has `minSize >= 1`** (or 2 for HA) so capacity is always available without Karpenter.
3. **Uses the same instance type family** as the Karpenter NodePool (e.g. `t3a.medium` for x86 Vendure) so resource requests fit.
4. **Spans multiple AZs** if you need zone resilience when Karpenter is down (e.g. create node group with subnets in 2–3 AZs).

**Reference:** `helm/environments/production/eks-nodegroups.yaml` — **NODE GROUP 2: APPLICATION (app-v4)** is the intended fallback:

- **Purpose:** Spillover + fallback when Karpenter is unavailable.
- **minSize:** Keep at least 1 (2 for HA).
- **Labels:** `node-group=app`, `node-type=on-demand`, `workload=vendure`.
- **Instance:** `t3a.medium` (x86) to match Vendure image and Karpenter NodePool.

If you run **only** Karpenter for app capacity (no managed app node group), then when Karpenter is down:

- Existing pods keep running.
- New or rescheduled pods (e.g. after a node drain, or HPA scale-up) will stay **Pending** until Karpenter is back or you add a managed node group.

---

## 3. Runbooks

### 3.1 Karpenter controller crashed or not running

1. **Check controller:**
   ```bash
   kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter
   kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f --tail=100
   ```
2. **If pod is CrashLoopBackOff or missing:** Restart or reinstall:
   ```bash
   kubectl delete pod -n kube-system -l app.kubernetes.io/name=karpenter
   # If installed via Helm:
   helm upgrade karpenter oci://public.ecr.aws/karpenter/karpenter -n kube-system ...
   ```
3. **Pending pods:** Ensure fallback node group (e.g. `app-v4`) exists and has capacity; scale it if needed:
   ```bash
   kubectl get nodes -l node-group=app
   aws eks update-nodegroup-config --cluster-name <cluster> --nodegroup-name app-v4 \
     --scaling-config minSize=1,maxSize=3,desiredSize=2 --region ap-south-1
   ```

### 3.2 AWS API throttling (Karpenter logs show throttle errors)

1. **Check logs:**
   ```bash
   kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -f | grep -i throttle
   ```
2. **Karpenter** uses exponential backoff; provisioning will resume when throttling eases.
3. **Short-term:** Rely on fallback node group so existing + minimal new pods can schedule; avoid large scale-ups until throttling subsides.
4. **Long-term:** Consider AWS Service Quotas for EC2/RunInstances and/or reduce churn (e.g. less aggressive consolidation).

### 3.3 No fallback node group yet

1. Add a managed node group with the same labels as app workloads (`node-group=app`). See `eks-nodegroups.yaml` **NODE GROUP 2** for the exact `aws eks create-nodegroup` command and labels.
2. Use **minSize=1** (or 2 for HA) so there is always at least one node that accepts `node-group=app` pods.
3. Document in this file and in `eks-nodegroups.yaml` that this group is the **Karpenter failover** capacity.

---

## 4. Checklist (Reportable)

- [ ] **Fallback managed node group** exists for app workloads (e.g. `app-v4`) with `node-group=app`, minSize ≥ 1.
- [ ] **Sizing:** Fallback can run at least Vendure `minReplicas` + worker (or your minimum production footprint).
- [ ] **Karpenter** runs on platform node group (not on Karpenter-provisioned nodes) so controller recovery does not depend on its own provisioning.
- [ ] **Runbooks** above are known to on-call; link this doc from your wiki or alert runbooks.
- [ ] **Alerts** (optional): Alert on Karpenter pod not Ready or on high count of Pending pods with `node-group=app` when no Karpenter nodes are being created.

---

## 5. References

| Doc / File | Description |
|------------|-------------|
| `helm/environments/production/eks-nodegroups.yaml` | Node group definitions; **NODE GROUP 2** = fallback app capacity. |
| `helm/karpenter/README.md` | Karpenter install, NodePools, troubleshooting. |
| `helm/argocd/applications/karpenter.yaml` | Argo CD application for Karpenter NodePools/EC2NodeClass (not the controller Helm install). |

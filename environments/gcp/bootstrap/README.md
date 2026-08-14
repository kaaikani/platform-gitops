# GKE escape cluster — bootstrap

Five things must exist on the cluster before any app chart is installed. All
four are idempotent; run them again if you are unsure whether they took.

Nothing in this directory is read by ArgoCD. It applies only to a cluster that
exists during an escape or an escape drill.

---

## 0. Get a kubeconfig

```bash
gcloud container clusters get-credentials kaaikani-escape \
  --region asia-south1 --project kaaikani-escape
```

## 1. TLS material — ALREADY DONE (2026-08-13)

A self-signed certificate covering all four Cloudflare-fronted zones is stored
in Secret Manager as `cf_origin_tls_crt` / `cf_origin_tls_key`. Valid to 2041.
Nothing to do before an escape.

Self-signed rather than Cloudflare Origin CA because the Origin CA Key is
deprecated and the replacement token permission was not available on this
account. The only consequence is the Cloudflare SSL mode used on escape day.

⚠ **On escape day, set Cloudflare SSL/TLS mode to `Full` for the four zones.**
NOT `Full (strict)` — strict validates the origin certificate and a self-signed
one fails it with error 526. Traffic is still fully encrypted either way;
`Full` simply does not verify the origin's issuer.

**Do not change this setting now.** Production serves from AWS with real ACM
certificates, where `Full (strict)` is correct. Changing it early weakens live
traffic for no benefit.

Load it into the cluster during an escape:

```bash
gcloud secrets versions access latest --secret=cf_origin_tls_crt --project kaaikani-escape > /tmp/o.crt
gcloud secrets versions access latest --secret=cf_origin_tls_key --project kaaikani-escape > /tmp/o.key
kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
kubectl -n ingress-nginx create secret tls cf-origin-tls --cert=/tmp/o.crt --key=/tmp/o.key
shred -u /tmp/o.crt /tmp/o.key
```

## 2. external-secrets operator

```bash
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
kubectl -n external-secrets create serviceaccount external-secrets \
  --dry-run=client -o yaml | kubectl apply -f -
# The GSA binding is already applied by terraform; this annotation is the
# Kubernetes half of the same link.
kubectl -n external-secrets annotate serviceaccount external-secrets \
  iam.gke.io/gcp-service-account=external-secrets@kaaikani-escape.iam.gserviceaccount.com --overwrite

helm repo add external-secrets https://charts.external-secrets.io
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --set serviceAccount.create=false \
  --set serviceAccount.name=external-secrets --wait

kubectl apply -f environments/gcp/bootstrap/cluster-secret-store.yaml
```

Verify before going further — an unhealthy store means every app below comes up
with no environment and crash-loops in a way that looks like a database
problem:

```bash
kubectl get clustersecretstore gcp-secrets -o jsonpath='{.status.conditions[0].type}'   # want: Ready
```

## 3. ingress-nginx

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  -n ingress-nginx --create-namespace \
  -f environments/gcp/bootstrap/ingress-nginx-values.yaml --wait

kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

That IP is what every Cloudflare record points at in the final step of the
escape. One address, all six hostnames.

## 4. Storefront secrets

The storefront charts read a plain `storefront-secrets` Secret rather than an
ExternalSecret, so it is created directly from the mirrored copy:

⚠ **Each release expects its OWN secret name**, not a shared one — this was
AWS drill #3 finding #17, and it presents as `CreateContainerConfigError` with
no obvious cause. The names are not derivable from the namespace; they are
whatever each values file pins:

| Release | Secret name |
|---|---|
| storefront-production | `storefront-secrets` |
| southmithai-production | `southmithai-secrets` |
| swadkerala-production | `swadkerala-secrets` |

```bash
for pair in storefront-production:storefront-secrets \
            southmithai-production:southmithai-secrets \
            swadkerala-production:swadkerala-secrets; do
  ns=${pair%%:*}; sec=${pair##*:}
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  gcloud secrets versions access latest --secret=prod_storefronts --project kaaikani-escape \
    | jq -r 'to_entries[] | "--from-literal=\(.key)=\(.value)"' \
    | xargs kubectl -n "$ns" create secret generic "$sec"
done
```

prabasaari-production pins no `existingSecret` — confirm during drill #2
whether it needs one before assuming it does not.

## 5. ArgoCD (optional but recommended)

Turns escape day from six hand-typed helm commands into one apply. Under
pressure, a forgotten `-f` or a wrong namespace is a real failure mode; this
removes it. Regional DR already does this — drill #3 had ArgoCD Synced/Healthy.

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace \
  --set configs.params."server\.insecure"=true --wait

kubectl apply -f environments/gcp/argocd/applications.yaml
kubectl -n argocd get applications -w        # all six -> Synced / Healthy
```

`server.insecure` is set because ingress-nginx terminates TLS in front of it;
without it ArgoCD serves its own self-signed cert and the proxy loops on
redirects. There is no ArgoCD ingress at all by default — reach the UI with
`kubectl port-forward svc/argocd-server -n argocd 8080:80`. During an outage the
dashboard is for you, not the public.

⚠ **DRILL MODE: do not use these Applications.** They deploy the escape
configuration — real Redis Cloud credentials, real integration keys, real
hostnames. A drill run through them would share production's job queue. For
drills use the helm commands with `-f environments/gcp/drill-values.yaml`.

⚠ These Applications live in `environments/gcp/argocd/`, which the production
app-of-apps does not read (it watches `argocd/applications` only). Never move
this file into `argocd/applications/` — production ArgoCD would immediately try
to apply GKE-shaped config to the EKS cluster.

---

## What is deliberately NOT installed

Skipped because the cost of installing them during an outage exceeds their
value in the hours the escape cluster is expected to live:

| Not installed | What replaces it during an escape |
|---|---|
| Prometheus / Grafana / Loki / Tempo | Cloud Logging + Cloud Monitoring, on by default in Autopilot — `gcloud logging tail` and the Metrics Explorer |

| Karpenter | Autopilot provisions nodes itself; that is the reason Autopilot was chosen |
| Velero | The escape cluster holds no state worth backing up — the data is in Cloud SQL and GCS |
| Kyverno / trivy-operator | Policy enforcement on a single-tenant cluster running known images, during an outage |
| Argo Rollouts | Blue/green deploys during a disaster are not wanted; the storefront overlay switches to plain Deployments |

This is a deliberate scope decision, not an oversight. If an escape ever runs
long enough that these matter, the platform has stopped being in an outage and
is being rebuilt — a different exercise with different priorities.

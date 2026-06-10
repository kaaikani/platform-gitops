#!/usr/bin/env python3
"""
Generate Grafana dashboard ConfigMaps from the source JSON dashboards.

Single source of truth:  monitoring-stack/dashboards/<category>/<name>.json
Generated (do not hand-edit):
    monitoring-stack/dashboard-configmaps.yaml      (metric dashboards)
    monitoring-stack/dashboard-vendure-client.yaml  (vendure-client app + logs)
    monitoring-stack/vendure-logs-dashboard.yaml    (Loki - vendure logs)
    monitoring-stack/storefronts-logs-dashboard.yaml(Loki - storefront logs)

The grafana sidecar provisions any ConfigMap labelled grafana_dashboard="1";
the grafana_folder annotation places it in a folder. ArgoCD app
`monitoring-dashboards` applies monitoring-stack/*.yaml into the monitoring ns.

Run after editing any source dashboard:
    python3 scripts/monitoring/build-dashboards.py
"""
import json, os, sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(REPO, "monitoring-stack", "dashboards")
OUT = os.path.join(REPO, "monitoring-stack")

# src (relative to SRC) -> (configmap name, grafana folder, data key, output file)
MANIFEST = [
    ("sre-core/sre-overview.json",            "dashboard-sre-overview",              "SRE",                          "sre-overview.json",            "dashboard-configmaps.yaml"),
    ("vendure/vendure-application.json",       "dashboard-vendure-application",       "Vendure",                      "vendure-application.json",     "dashboard-configmaps.yaml"),
    ("storefronts/storefronts-overview.json",  "dashboard-storefronts-overview",      "Storefronts",                  "storefronts-overview.json",    "dashboard-configmaps.yaml"),
    ("kubernetes/cluster-overview.json",       "dashboard-k8s-cluster-overview",      "Kubernetes",                   "cluster-overview.json",        "dashboard-configmaps.yaml"),
    ("database/mysql-rds.json",                "dashboard-mysql-rds",                 "Database",                     "mysql-rds.json",               "dashboard-configmaps.yaml"),
    ("cache/redis.json",                       "dashboard-redis-cache",               "Cache",                        "redis.json",                   "dashboard-configmaps.yaml"),
    ("cloudflare/cloudflare-analytics.json",   "dashboard-cloudflare-analytics",      "Cloudflare",                   "cloudflare-analytics.json",    "dashboard-configmaps.yaml"),
    ("vendure/vendure-client-application.json","dashboard-vendure-client-application","Vendure - prabhasaaridesigns", "vendure-client-application.json","dashboard-vendure-client.yaml"),
    ("logs/vendure-client-logs.json",          "vendure-client-logs-dashboard",       "Vendure - prabhasaaridesigns", "vendure-client-logs.json",     "dashboard-vendure-client.yaml"),
    ("logs/vendure-logs.json",                 "vendure-logs-dashboard",              "Vendure",                      "vendure-logs.json",            "vendure-logs-dashboard.yaml"),
    ("logs/storefronts-logs.json",             "storefronts-logs-dashboard",          "Storefronts",                  "storefronts-logs.json",        "storefronts-logs-dashboard.yaml"),
]

HEADER = (
    "# =============================================================================\n"
    "# GENERATED FILE - do not edit by hand.\n"
    "# Source: monitoring-stack/dashboards/**/*.json\n"
    "# Regenerate: python3 scripts/monitoring/build-dashboards.py\n"
    "# =============================================================================\n"
)

def configmap_yaml(cm, folder, key, body):
    # Embed the source JSON verbatim (only re-indented) so dashboards that did
    # not change produce no diff. Trailing newline trimmed; each line indented 4.
    lines = body.rstrip("\n").split("\n")
    indented = "\n".join(("    " + line).rstrip() for line in lines)
    return (
        "---\n"
        "apiVersion: v1\n"
        "kind: ConfigMap\n"
        "metadata:\n"
        f"  name: {cm}\n"
        "  namespace: monitoring\n"
        "  labels:\n"
        '    grafana_dashboard: "1"\n'
        "  annotations:\n"
        f'    grafana_folder: "{folder}"\n'
        "data:\n"
        f"  {key}: |\n"
        f"{indented}\n"
    )

def main():
    by_out = {}
    for src, cm, folder, key, outfile in MANIFEST:
        path = os.path.join(SRC, src)
        with open(path) as f:
            body = f.read()
        json.loads(body)                 # validates JSON
        by_out.setdefault(outfile, []).append(configmap_yaml(cm, folder, key, body))
    for outfile, blocks in by_out.items():
        with open(os.path.join(OUT, outfile), "w") as f:
            f.write(HEADER + "".join(blocks))
        print(f"wrote {outfile}  ({len(blocks)} dashboard configmap(s))")

if __name__ == "__main__":
    main()

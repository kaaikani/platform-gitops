#!/usr/bin/env python3
"""Extract every panel target from the deployed dashboard configmaps and test
each query against live Prometheus / Loki. Report which panels return data."""
import sys, json, glob, time, urllib.parse, urllib.request, re
import yaml

PROM = "http://localhost:9090"
LOKI = "http://localhost:3100"
NOW = 1781068279  # fixed-ish; we use range relative to server time via special_value

def http_get(url):
    try:
        with urllib.request.urlopen(url, timeout=25) as r:
            return json.load(r)
    except Exception as e:
        return {"_error": str(e)}

def prom_query(expr):
    # instant query at current server time
    expr = subst(expr)
    u = PROM + "/api/v1/query?" + urllib.parse.urlencode({"query": expr})
    d = http_get(u)
    if d.get("_error"): return ("ERR", d["_error"][:80])
    if d.get("status") != "success": return ("ERR", str(d.get("error"))[:80])
    n = len(d["data"]["result"])
    return ("DATA" if n>0 else "EMPTY", n)

VARS = {
    "$namespace": "storefront-production",
    "$container": "vendure",
    "$level": "error|warn|warning|info",
    "$zone": ".+",
    "$pod": ".+",
    "$__rate_interval": "5m",
    "$__interval": "5m",
    "$__range": "1h",
}
def subst(expr):
    for k,v in VARS.items():
        expr = expr.replace(k, v)
    return expr

def loki_query(expr):
    expr = subst(expr)
    # range query last 24h
    end = int(time.time())*10**9
    start = end - 24*3600*10**9
    u = LOKI + "/loki/api/v1/query_range?" + urllib.parse.urlencode(
        {"query": expr, "start": start, "end": end, "limit": 5})
    d = http_get(u)
    if d.get("_error"): return ("ERR", d["_error"][:80])
    if d.get("status") != "success": return ("ERR", str(d.get("error"))[:80])
    n = len(d["data"]["result"])
    return ("DATA" if n>0 else "EMPTY", n)

def iter_dashboards(paths):
    for path in paths:
        with open(path) as f:
            docs = list(yaml.safe_load_all(f))
        for doc in docs:
            if not doc or doc.get("kind")!="ConfigMap": continue
            if "1" != str(doc.get("metadata",{}).get("labels",{}).get("grafana_dashboard","")): continue
            cmname = doc["metadata"]["name"]
            folder = doc["metadata"].get("annotations",{}).get("grafana_folder","?")
            for key, val in doc.get("data",{}).items():
                try:
                    dash = json.loads(val)
                except Exception as e:
                    print(f"!! {cmname}/{key} JSON parse error: {e}")
                    continue
                yield path, cmname, folder, key, dash

def panel_targets(panel):
    out=[]
    for t in panel.get("targets",[]) or []:
        expr = t.get("expr")
        ds = t.get("datasource")
        dstype = ""
        if isinstance(ds, dict): dstype = ds.get("type","")
        if expr: out.append((dstype, expr))
    return out

def classify(dstype, expr):
    # loki if datasource type loki, or looks like logql
    if dstype=="loki": return "loki"
    if dstype=="prometheus": return "prom"
    # guess
    if expr.strip().startswith("{") or "|=" in expr or "| json" in expr or "rate({" in expr:
        return "loki"
    return "prom"

paths = sys.argv[1:]
total_data=total_empty=total_err=0
for path, cmname, folder, key, dash in iter_dashboards(paths):
    title = dash.get("title", key)
    panels = dash.get("panels",[])
    # flatten rows
    flat=[]
    for p in panels:
        flat.append(p)
        for sp in p.get("panels",[]) or []:
            flat.append(sp)
    print(f"\n===== [{folder}] {title}  ({cmname})  file={path}")
    d=e=err=0
    for p in flat:
        ptitle = p.get("title","")
        ptype = p.get("type","")
        if ptype in ("row","text","dashlist","news"): continue
        tgts = panel_targets(p)
        if not tgts:
            continue
        for dstype, expr in tgts:
            kind = classify(dstype, expr)
            if kind=="loki":
                status,info = loki_query(expr)
            else:
                status,info = prom_query(expr)
            mark = {"DATA":"  ok","EMPTY":"EMPTY","ERR":" ERR"}[status]
            if status=="DATA": d+=1
            elif status=="EMPTY": e+=1
            else: err+=1
            if status!="DATA":
                print(f"   [{mark}] {ptitle!r:45.45} <{kind}> {expr[:90]}")
    print(f"   -- panel-targets: DATA ok would-be; EMPTY={e} ERR={err} (only non-DATA shown)")
    total_data+=d; total_empty+=e; total_err+=err
print(f"\n##### TOTAL across dashboards: EMPTY(no-data)={total_empty} ERR={total_err}")

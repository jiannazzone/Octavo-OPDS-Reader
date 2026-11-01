"""timeline.py <run.jsonl> [move...]: page and app events of each move, merged in time order."""
import json, sys, datetime
for line in open(sys.argv[1]):
    r = json.loads(line)
    if sys.argv[2:] and r["move"] not in sys.argv[2:]: continue
    print("==", r["move"], "renders", r.get("renders"), r.get("counts"))
    rows = []
    for e in r["events"]:
        w = datetime.datetime.fromtimestamp(e["wall"] / 1000, datetime.timezone.utc).strftime("%H:%M:%S.%f")[:-3]
        if e["type"] == "attr": d = f'{e.get("name")}={e.get("value")}'
        else: d = e.get("reason") or e.get("by") or e.get("key") or e.get("style") or ""
        rows.append((w, "page ", e["type"], f'{e["w"]}x{e["h"]}', d))
    for s in r["swift"]:
        ev = s["event"]
        if ev == "hinge": d = f'{s.get("old")} -> {s.get("new")}'
        elif ev == "geometry":
            divs = [(x["frame"], x["active"]) for x in s["regions"] if x["kind"] == "division"]
            d = f'size {s["size"]} div {divs} screen {s["scenes"][0]["screen"]}'
        else: d = json.dumps({k: v for k, v in s.items() if k not in ("t", "process", "instance", "event")})[:160]
        rows.append((s["t"], "swift", ev, "", d))
    for row in sorted(rows): print(" ".join(str(x) for x in row)[:240])

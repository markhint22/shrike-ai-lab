import json,datetime,collections,sys,os,re,subprocess,pickle
sys.path.insert(0,'scripts')
import ovn_failure_triage as T
rows=[]
for l in open("state/outcomes.jsonl"):
    try: rows.append(json.loads(l,strict=False))
    except Exception: pass
now=datetime.datetime.now(datetime.timezone.utc)
cut=(now-datetime.timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%SZ")
r=[x for x in rows if x["ts"]>=cut and not x["status"].startswith(("skip","error"))]
idx=T._build_run_dir_index("logs")
def git(repo,*a):
    return subprocess.run(["git","-C",f"repos/{repo}",*a],capture_output=True,text=True,errors="replace").stdout
shacache={}; progcache={}
def prog_at(repo,ts):
    key=(repo,ts[:13]+str(int(ts[14:16])//10))
    if key in shacache: sha=shacache[key]
    else:
        sha=git(repo,"rev-list","-1",f"--before={ts}","overnight/feature").strip()
        shacache[key]=sha
    if not sha: return sha,""
    if (repo,sha) not in progcache:
        progcache[(repo,sha)]=git(repo,"show",f"{sha}:OVERNIGHT_PROGRESS.md")
    return sha,progcache[(repo,sha)]
SKIP=re.compile(r"HUMAN-ONLY|AUTO-SKIP|HARD FILE BAN|BLOCKED|\[CLAUDE\]",re.I)
out=[]
for x in r:
    ep=datetime.datetime.fromisoformat(x["ts"].replace("Z","+00:00")).timestamp()
    p=T.find_task_log("logs",idx,x["id"],ep)
    txt=open(p,errors="replace").read(70000) if p else ""
    m=re.search(r"VERDICT:.*?(?=\nTokens:)",txt,re.S)
    sc=re.sub(r"\s+"," ",m.group(0)) if m else ""
    # scouted files as in lib_item_select
    blk=[]
    mm=re.search(r"VERDICT:\s*(?:PROCEED|NEEDS-DECISION).*",txt,re.I|re.S)
    scouted=[]
    if mm:
        seg="\n".join(mm.group(0).splitlines()[:5])
        scouted=re.findall(r"[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}",seg)
    for l in re.findall(r"FILES:.*",txt): scouted+=re.findall(r"[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}",l)
    scouted=[s for s in dict.fromkeys(scouted) if not s.endswith(".md")]
    tsx=(datetime.datetime.fromisoformat(x["ts"].replace("Z","+00:00"))-datetime.timedelta(seconds=int(x.get("duration_s",0) or 0)+90)).strftime("%Y-%m-%dT%H:%M:%SZ")
    sha,pg=prog_at(x["repo"],tsx)
    lines=[(i+1,l) for i,l in enumerate(pg.splitlines()) if re.match(r"^- \[ \]",l) and not SKIP.search(l)]
    item=None; conf=False
    for f in scouted:
        for i,l in lines:
            if f in l: item=l;conf=True;break
        if item:break
    if not item and lines: item=lines[0][1]
    out.append(dict(ts=x["ts"],repo=x["repo"],status=x["status"],fr=x.get("fail_reason"),dur=x.get("duration_s",0),sev=x["severity"],hash=x.get("item_hash",""),sha=sha,item=item or "",scout=sc[:300],log=p,conf=conf,verdict=(re.match(r"VERDICT:\s*(\S+)",sc).group(1) if sc else "")))
pickle.dump(out,open("/tmp/g.pkl","wb"))
print(len(out), sum(1 for o in out if o["item"]))

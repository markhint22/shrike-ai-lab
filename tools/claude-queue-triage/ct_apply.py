import sys,re,subprocess,os,shutil,time
repo, dry = sys.argv[1], (sys.argv[2]=="dry")
CLONE=f"/Users/mhintermeister/LocalProjects/{repo}"
WT=f"/tmp/wt-cta-{repo}"
def sh(*a,cwd=None,check=True):
    r=subprocess.run(a,cwd=cwd,capture_output=True,text=True)
    if check and r.returncode: raise SystemExit(f"{' '.join(a)} -> {r.stderr[:200]}")
    return r.stdout
rows=[l.rstrip("\n").split("\t",2) for l in open(f"/tmp/ct_{repo}.tsv") if not l.startswith("DONE")]
NOTE=re.compile(r'recovered/decomposed|hard-banned|^- \[ \] \[CLAUDE\] (The |This |Task |No |I |It |Both |Since |Given |Based |Both )')
PROTECT=re.compile(r'bug-escalated|EMERGENCY')
shutil.rmtree(WT,ignore_errors=True); sh("git","-C",CLONE,"worktree","prune",check=False)
for attempt in range(5):
    sh("git","-C",CLONE,"fetch","-q","origin","overnight/feature")
    sh("git","-C",CLONE,"worktree","remove","--force",WT,check=False); shutil.rmtree(WT,ignore_errors=True)
    sh("git","-C",CLONE,"worktree","add","-q","--detach",WT,"origin/overnight/feature")
    p=os.path.join(WT,"OVERNIGHT_PROGRESS.md")
    data=open(p,"rb").read().decode("utf-8","surrogateescape")
    L=data.split("\n")
    ticked=dismissed=skipped=0; why=[]
    for ln,res,txt in rows:
        if PROTECT.search(txt): skipped+=1; continue
        kind=None
        if res=="PASS": kind="pass"
        elif res=="NO_VERIFY_CLAUSE" and NOTE.search(txt): kind="note"
        if not kind: continue
        m=[i for i,l in enumerate(L) if l.startswith("- [ ] ") and l.startswith(txt[:200]) and "CLAUDE" in l]
        if len(m)!=1: skipped+=1; why.append((len(m),txt[:60])); continue
        i=m[0]
        tag=("(already-satisfied: item's own VERIFY passes - Claude-queue triage 2026-10-07) " if kind=="pass"
             else "(dismissed 2026-10-07: diagnostic note, not a work item - the underlying work is tracked by the item lines with a VERIFY clause) ")
        L[i]="- [x] "+tag+L[i][len("- [ ] "):]
        if kind=="pass": ticked+=1
        else: dismissed+=1
    print(f"{repo}: would tick {ticked} already-satisfied, dismiss {dismissed} notes, skipped {skipped} (ambiguous/protected); unmatched sample: {why[:3]}")
    if dry: break
    open(p,"wb").write("\n".join(L).encode("utf-8","surrogateescape"))
    diff=sh("git","diff","--numstat",cwd=WT).split()
    if not (ticked+dismissed): print("nothing to change"); break
    if diff[:2]!=[str(ticked+dismissed)]*2: raise SystemExit(f"unexpected diff {diff}")
    sh("git","add","OVERNIGHT_PROGRESS.md",cwd=WT)
    sh("git","-c","user.name=shrike-fleet","-c","user.email=22970726+markhint22@users.noreply.github.com","-c","commit.gpgsign=false","commit","-q","-m",f"chore(queue): Claude-queue triage - tick {ticked} already-satisfied (own VERIFY passes), dismiss {dismissed} non-actionable diagnostic notes\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>",cwd=WT)
    r=subprocess.run(["git","push","-q","origin","HEAD:overnight/feature"],cwd=WT,capture_output=True,text=True)
    if r.returncode==0: print(f"pushed {sh('git','rev-parse','--short','HEAD',cwd=WT).strip()} on attempt {attempt+1}"); break
    print("push rejected, re-applying on the new tip"); time.sleep(3)
sh("git","-C",CLONE,"worktree","remove","--force",WT,check=False); sh("git","-C",CLONE,"worktree","prune",check=False)

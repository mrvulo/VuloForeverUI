import re,json,sys
def parse(s,name):
    i=s.index(name+' = ')+len(name)+3
    tok=re.compile(r'\s*(?:(\{)|(\})|(,)|(;)|\[\s*("(?:[^"\\]|\\.)*"|-?[\d.e+-]+)\s*\]\s*=|("(?:[^"\\]|\\.)*")|(true|false|nil)|(-?(?:0x[0-9a-fA-F]+|[\d.]+(?:[eE][+-]?\d+)?)))',re.S)
    pos=[i]
    def val():
        m=tok.match(s,pos[0]); pos[0]=m.end()
        if m.group(1):
            t={}; n=1
            while True:
                m2=tok.match(s,pos[0])
                if m2.group(2): pos[0]=m2.end(); return t
                if m2.group(3) or m2.group(4): pos[0]=m2.end(); continue
                if m2.group(5):
                    pos[0]=m2.end(); k=m2.group(5)
                    k=json.loads(k) if k.startswith('"') else (int(float(k)) if float(k).is_integer() else float(k))
                    t[k]=val()
                else:
                    t[n]=val(); n+=1
        if m.group(6): return json.loads(m.group(6).replace('\\\n','\\n'))
        if m.group(7): return {'true':True,'false':False,'nil':None}[m.group(7)]
        if m.group(8): 
            v=m.group(8); return int(v,16) if v.startswith('0x') else (int(v) if re.fullmatch(r'-?\d+',v) else float(v))
        raise Exception('bad at %d: %r'%(pos[0],s[pos[0]:pos[0]+40]))
    return val()
# ---------------------------------------------------------------------------
# tools/ship_profile.py -- turn one saved profile into the shipped defaults.
#
#   python3 tools/ship_profile.py [SavedVariables file] [profile name]
#
# Reads the account SavedVariables (default: ~/addons/_SavedVariables/
# VuloForeverUI.lua, the copy that comes back from the gaming PC), takes the
# named profile (default: the active one) and writes Core/Database/Shipped.lua.
# Left out on purpose -- see the header of the generated file for why:
SKIP = {
    ("modules", "cooldownmanager"),                 # bars hold class spell lists and an order array
    ("modules", "bags", "sortRefused"),             # what the sort learned it may not move
    ("modules", "damagemeter", "bookmarks"),        # a list
    ("modules", "damagemeter", "classicSeeded"),    # one-time migration marker
    ("modules", "nameplates", "savedCVars"),        # the player's own client values, kept to restore
    ("modules", "nameplates", "savedStacking"),
}
SKIP_KEYS = {"seeded", "_filled"}                    # state markers wherever they sit
MODULES_OFF = ["cooldownmanager"]                    # every other module ships on

def strip(t, path=()):
    out = {}
    for k, v in t.items():
        p = path + (str(k),)
        if p in SKIP or str(k) in SKIP_KEYS:
            continue
        if isinstance(v, dict):
            v = strip(v, p)
            if not v:
                continue
        out[k] = v
    return out

def lua(v, ind=1):
    pad = "    " * ind
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v) if isinstance(v, float) else str(v)
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, dict):
        if not v:
            return "{}"
        rows = []
        for k in sorted(v, key=lambda k: (isinstance(k, str), str(k))):
            key = ("[%d]" % k) if isinstance(k, int) else (k if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", k) else "[%s]" % json.dumps(k, ensure_ascii=False))
            rows.append("%s%s = %s," % (pad, key, lua(v[k], ind + 1)))
        return "{\n" + "\n".join(rows) + "\n" + "    " * (ind - 1) + "}"
    raise TypeError(v)

if __name__ == "__main__":
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/addons/_SavedVariables/VuloForeverUI.lua")
    db = parse(open(src, encoding="utf-8").read(), "VuloForeverUIDB")
    name = sys.argv[2] if len(sys.argv) > 2 else db.get("activeProfile", "Default")
    prof = strip(db["profiles"][name])
    modules = prof.pop("modules", {})
    glob = {k: db["global"][k] for k in ("fonts", "classColors", "powerColors") if db["global"].get(k)}
    body = {"global": glob, "profile": prof, "modules": modules, "modulesOff": {m: True for m in MODULES_OFF}}
    head = open(os.path.join(here, "ship_profile_header.lua"), encoding="utf-8").read()
    out = head.replace("@PROFILE@", name) + "local SHIPPED = " + lua(body) + "\n\n" + open(os.path.join(here, "ship_profile_footer.lua"), encoding="utf-8").read()
    dst = os.path.join(here, "..", "Core", "Database", "Shipped.lua")
    open(dst, "w", encoding="utf-8").write(out)
    print("wrote", os.path.normpath(dst), "from profile", name, "-", len(modules), "modules")

"""Conservative tracked-file guard. Never prints matched values. Not a full secret detector."""
from pathlib import Path
import subprocess,re,sys
root=Path(__file__).resolve().parents[1]
try:
    names=subprocess.check_output(['git','ls-files','-z'],cwd=root).decode().split('\0')
except (OSError,subprocess.CalledProcessError):
    print('Tracked-file safety requires a Git checkout.');sys.exit(1)
bad=[]
for name in filter(None,names):
    p=root/name
    if not p.is_file():continue
    if any(x in p.parts for x in ('.godot','__pycache__','node_modules')) or p.suffix.lower() in ('.pem','.key','.exe','.pck','.zip','.log','.pyc') or p.name=='.env':
        bad.append((name,'private/generated file type'))
    if p.stat().st_size>20*1024*1024:bad.append((name,'large file; review'))
    if p.suffix.lower() in ('.gd','.py','.md','.json','.cfg','.env','.sh','.ps1','.cmd'):
        text=p.read_text(encoding='utf-8',errors='replace')
        if re.search(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE' + r' KEY-----',text):bad.append((name,'private key material'))
for name,reason in bad:print(name+': '+reason)
print('Repository guard:',len(bad),'findings; manual credential and asset review still required.')
sys.exit(bool(bad))

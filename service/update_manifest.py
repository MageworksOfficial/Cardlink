"""Independent, bounded update metadata. No room, relay or gameplay imports."""
import json
import re
import time
from pathlib import Path
from urllib.parse import urlsplit

MAX_BYTES = 65536
REPOSITORY = "MageworksOfficial/Cardlink"

def version(value):
    if not isinstance(value, str) or not re.fullmatch(r"[vV]?\d{1,6}(?:\.\d{1,6}){2,3}(?:-beta)?", value):
        raise ValueError("invalid version")
    parts = [int(x) for x in value.lstrip("vV").removesuffix("-beta").split(".")]
    return tuple(parts + [0] * (4-len(parts)) + [0 if value.endswith("-beta") else 1])

def github_url(value, asset=False):
    prefix = f"https://github.com/{REPOSITORY}/releases/"
    if not isinstance(value, str) or len(value)>2048 or any(ord(x)<=32 for x in value): return False
    if any(x in value for x in ("..", "%", "?", "#", "\\")): return False
    return value.startswith(prefix+"download/") if asset else (value.startswith(prefix+"tag/") or value==prefix+"latest")

def validate(data):
    if not isinstance(data, dict): raise ValueError("manifest must be an object")
    latest = version(data.get("latest_version")); minimum = version(data.get("minimum_online_version"))
    if minimum > latest: raise ValueError("minimum exceeds latest")
    if data.get("update_level") not in ("optional", "recommended", "required"): raise ValueError("update level")
    if not github_url(data.get("release_url")): raise ValueError("release URL")
    directory = data.get("server_directory_url", "")
    if directory:
        if not isinstance(directory,str) or len(directory)>2048: raise ValueError("directory URL")
        url = urlsplit(directory)
        if url.scheme!="https" or not url.netloc or url.username or any(ord(c)<=32 for c in directory): raise ValueError("directory URL")
    assets = data.get("assets")
    if not isinstance(assets,dict) or len(assets)>8: raise ValueError("assets")
    clean = {}
    for platform, asset in assets.items():
        if not isinstance(platform,str) or len(platform)>40 or not isinstance(asset,dict): raise ValueError("platform")
        if not github_url(asset.get("url"),True): raise ValueError("asset URL")
        if not isinstance(asset.get("sha256"),str) or not re.fullmatch(r"[a-fA-F0-9]{64}",asset["sha256"]): raise ValueError("asset digest")
        if type(asset.get("size")) is not int or not 1<=asset["size"]<=10737418240: raise ValueError("asset size")
        clean[platform] = {k:asset[k] for k in ("url","sha256","size")}
    result = {k:data[k] for k in ("latest_version","minimum_online_version","update_level","release_url")}
    result["assets"]=clean
    if directory: result["server_directory_url"]=directory
    return result

class UpdateManifest:
    """Reload an operator-owned JSON at most once per 10 seconds on demand.
    Invalid replacements fail closed to unavailable, not stale retirement policy.
    """
    def __init__(self, path=None, clock=time.monotonic):
        self.path=Path(path) if path else Path(__file__).with_name("update_manifest.json")
        self.clock=clock; self.checked=None; self.value=None
    def get(self):
        current=self.clock()
        if self.checked is None or current-self.checked>=10:
            self.checked=current;self.value=None
            try:
                with self.path.open("rb") as f: raw=f.read(MAX_BYTES+1)
                if len(raw)>MAX_BYTES: raise ValueError("oversized manifest")
                self.value=validate(json.loads(raw))
            except (OSError,ValueError,TypeError,RecursionError): pass
        if self.value is None: return {"error":"update_status_unavailable"}
        return self.value

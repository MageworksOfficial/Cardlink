"""Publisher-only: verify a deployed TLS service, embed config in an isolated export.
Requires the CardLink source project, Python 3.11+, Godot and Windows export templates.
Never modifies the original project's development configuration.
"""
import argparse
import json
import pathlib
import re
import shutil
import socket
import ssl
import subprocess
import tempfile
import urllib.request
import urllib.parse
import zipfile

def verify(url):
    if not re.fullmatch(r'https://[A-Za-z0-9.-]+(?::[0-9]{1,5})?/?',url):
        raise ValueError('Use the deployed HTTPS service hostname and optional port.')
    request=urllib.request.Request(url.rstrip('/')+'/v1/health',data=b'{}',headers={'Content-Type':'application/json'})
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs): return None
    opener=urllib.request.build_opener(urllib.request.HTTPSHandler(context=ssl.create_default_context()),NoRedirect())
    with opener.open(request,timeout=15) as reply:
        health=json.loads(reply.read(8193))
    if health.get('service')!='cardlink-rendezvous' or health.get('api')!=1 or health.get('protocol')!=1 or health.get('gameplay_relay') is not True or health.get('relay_tls') is not True:
        raise ValueError('Service must support protocol 1 gameplay relay with TLS.')
    hostname=health.get('relay_host') or urllib.parse.urlsplit(url).hostname
    port=health['relay_port']
    if not isinstance(hostname,str) or not re.fullmatch(r'[A-Za-z0-9.-]{1,253}',hostname) or type(port) is not int or not 1024<=port<=65535:
        raise ValueError('Invalid relay endpoint.')
    with socket.create_connection((hostname,port),timeout=15) as tcp:
        with ssl.create_default_context().wrap_socket(tcp,server_hostname=hostname) as conn:
            conn.sendall(b'{"probe":true}\n')
            line=b''
            while not line.endswith(b'\n') and len(line)<128:
                value=conn.recv(1)
                if not value:break
                line+=value
            if json.loads(line)!=dict(relay=True,protocol=1):raise ValueError('Relay probe failed.')
    return health

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project',type=pathlib.Path,required=True)
    parser.add_argument('--godot',required=True)
    parser.add_argument('--service-url',required=True)
    parser.add_argument('--output',type=pathlib.Path,required=True)
    args=parser.parse_args()
    health=verify(args.service_url)
    args.output.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='cardlink-publish-') as temporary:
        copy=pathlib.Path(temporary)/'source'
        shutil.copytree(args.project,copy,ignore=shutil.ignore_patterns('.godot','.git','__pycache__','*.zip','*.exe','*.pck','build','builds'))
        (copy/'config/network.cfg').write_text('[internet]\nservice_url='+json.dumps(args.service_url.rstrip('/'))+'\nrelay_host='+json.dumps(health.get('relay_host') or urllib.parse.urlsplit(args.service_url).hostname)+'\nrelay_port='+str(health['relay_port'])+'\ndirect_attempt_seconds=2.0\nrelay_enabled=true\nheartbeat_interval=2.0\nconnection_timeout=15.0\n',encoding='utf-8')
        for command in (['--headless','--editor','--import'],['--headless','--export-release','MILESTONE',str((args.output/'CardLink-7.exe').resolve())]):
            subprocess.run([args.godot,'--path',str(copy),*command],check=True,timeout=300)
    subprocess.run([args.godot,'--headless','--main-pack',str((args.output/'CardLink-7.pck').resolve()),'--script','res://scripts/tests/export_config_test.gd','--',args.service_url.rstrip('/')],check=True,timeout=30)
    (args.output/'SERVICE.txt').write_text('CardLink 7\nService: '+args.service_url+'\nProtocol: 1\nTLS service + relay verified during publishing.\n',encoding='utf-8')
    guide=args.project/'PLAYER_GUIDE_7.md'
    if guide.exists():shutil.copy2(guide,args.output/guide.name)
    with zipfile.ZipFile(args.output.with_suffix('.zip'),'w',zipfile.ZIP_DEFLATED) as z:
        for name in ('CardLink-7.exe','CardLink-7.pck','SERVICE.txt','PLAYER_GUIDE_7.md'):
            f=args.output/name
            if f.exists():z.write(f,name)
    print('Production build ready:',args.output.with_suffix('.zip'))

if __name__=='__main__':main()

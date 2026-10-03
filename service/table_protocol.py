"""Optional custom-table envelope. No card identities or library order in templates."""
import base64,math,re
KINDS={'deck','shared_deck','hand','discard','zone','leader','board','text','shared_area'}
FIELDS={'id','kind','name','owner','visibility','position','size','hidden','locked','rotation','opacity','asset','back','linked_pile','text'}
def number(v,lo,hi): return type(v) in (int,float) and math.isfinite(v) and lo<=v<=hi
def integer(v,lo,hi): return number(v,lo,hi) and v==int(v)
def text(v,n): return isinstance(v,str) and len(v)<=n and '\x00' not in v
def hx(v,n,empty=False): return isinstance(v,str) and ((empty and v=='') or re.fullmatch('[0-9a-f]{%d}'%n,v) is not None)
def pair(v,lo,hi): return isinstance(v,list) and len(v)==2 and all(number(x,lo,hi) for x in v)
def identifier(v): return isinstance(v,str) and re.fullmatch('[A-Za-z0-9_-]{1,80}',v) is not None
def table(v):
    if not isinstance(v,dict) or set(v)-{'defaults','background'} != {'format','id','name','description','author','dimensions','components'} or type(v['format']) not in (int,float) or v['format']!=1:return False
    if not hx(v['id'],32) or not text(v['name'],80) or not v['name'].strip() or not text(v['description'],1000) or not text(v['author'],80) or not pair(v['dimensions'],800,10000):return False
    if not isinstance(v['components'],list) or len(v['components'])>128:return False
    if 'background' in v:
        from appearance_protocol import background
        if not background(v['background']): return False
    defaults=v.get('defaults',[])
    if not isinstance(defaults,list) or len(defaults)+len(v['components'])>128:return False
    for item in defaults:
        if not isinstance(item,dict) or set(item)!={'kind','name','position','value','power','toughness','owner','controller'}:return False
        if item['kind'] not in ('token','counter') or not text(item['name'],80) or not pair(item['position'],-20000,20000) or not integer(item['value'],-1000000,1000000) or not text(item['power'],32) or not text(item['toughness'],32) or item['owner'] not in ('player_1','player_2') or item['controller'] not in ('player_1','player_2'):return False
    ids={}
    for c in v['components']:
        if not isinstance(c,dict) or set(c)!=FIELDS:return False
        if not hx(c['id'],32) or c['id'] in ids or not isinstance(c['kind'],str) or c['kind'] not in KINDS or not text(c['name'],80) or not c['name'].strip():return False
        if c['owner'] not in ('player_1','player_2','table') or c['visibility'] not in ('public','private'):return False
        if c['kind']=='shared_deck' and c['owner']!='table':return False
        if c['kind']=='hand' and c['owner']=='table':return False
        if not pair(c['position'],-20000,20000) or not pair(c['size'],40,8000) or not number(c['rotation'],-360,360) or not number(c['opacity'],.05,1):return False
        if type(c['hidden']) is not bool or type(c['locked']) is not bool or not hx(c['asset'],64,True) or not hx(c['back'],64,True) or not hx(c['linked_pile'],32,True) or not text(c['text'],1000):return False
        ids[c['id']]=c
    return all(not c['linked_pile'] or (c['linked_pile'] in ids and ids[c['linked_pile']]['kind'] in ('deck','shared_deck')) for c in v['components'])
def valid(v,session_id=None):
    if not isinstance(v,dict) or set(v)!={'type','protocol','session_id','kind','data'} or v['type']!='table_structure' or type(v['protocol']) not in (int,float) or v['protocol']!=1 or not hx(v['session_id'],32):return False
    if session_id and v['session_id']!=session_id:return False
    d=v['data'];k=v['kind']
    if not isinstance(d,dict):return False
    if k in ('table','edit'):return set(d)=={'table'} and table(d['table'])
    if k=='need':return set(d)=={'hash'} and hx(d['hash'],64)
    if k=='count':return set(d)=={'id','count'} and hx(d['id'],32) and integer(d['count'],0,5000)
    if k=='draw':return set(d)=={'id','player'} and hx(d['id'],32) and d['player'] in ('player_1','player_2')
    if k=='shuffle':return set(d)=={'id'} and hx(d['id'],32)
    if k=='place':return set(d)=={'id','card'} and hx(d['id'],32) and identifier(d['card'])
    if k=='members':return set(d)=={'id','cards'} and hx(d['id'],32) and isinstance(d['cards'],list) and len(d['cards'])<=500 and all(identifier(x) for x in d['cards'])
    if k=='draw_offer':return set(d)=={'id','request'} and hx(d['id'],32) and isinstance(d['request'],str) and d['request'].startswith('table_') and hx(d['request'][6:],32)
    if k=='image':
        if set(d)!={'hash','offset','total','bytes'} or not hx(d['hash'],64) or not integer(d['offset'],0,8388608) or not integer(d['total'],24,8388608) or not text(d['bytes'],43692):return False
        try:return len(base64.b64decode(d['bytes'],validate=True))<=32768
        except ValueError:return False
    return False

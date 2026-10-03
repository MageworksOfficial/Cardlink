"""Bounded wire schemas mirroring the reviewed Godot codecs; no persistence.

The relay validates structure, not game rules or inspection permission. Permission
and asset integrity remain enforced by the receiving client's existing services.
"""
import base64
import json
import math
import re

MAX_FRAME = 524288
PLAYERS = ('player_1', 'player_2')
def text(n=160): return lambda v: isinstance(v, str) and len(v) <= n
def num(lo, hi): return lambda v: type(v) in (int, float) and math.isfinite(v) and lo <= v <= hi
def integer(lo, hi): return lambda v: num(lo, hi)(v) and int(v) == v
def one(*values): return lambda v: type(v) in (str, int) and v in values
def boolean(v): return type(v) is bool
def obj(**fields): return lambda v: isinstance(v, dict) and set(v) == set(fields) and all(check(v[k]) for k, check in fields.items())
def arr(check, limit): return lambda v: isinstance(v, list) and len(v) <= limit and all(check(x) for x in v)
def unique(check, limit, key=lambda x:x):
    def valid(v):
        return arr(check,limit)(v) and len({key(x) for x in v}) == len(v)
    return valid
def mapping(check,limit): return lambda v: isinstance(v,dict) and len(v)<=limit and all(text(80)(k) and check(x) and k==x['id'] for k,x in v.items())
def hexstr(n): return lambda v: isinstance(v,str) and re.fullmatch('[0-9a-fA-F]{%d}'%n,v) is not None
identifier = lambda v: isinstance(v,str) and re.fullmatch(r'[A-Za-z0-9_-]{1,80}',v) is not None
hash_ok = lambda v: hexstr(64)(v) and v==v.lower()
art = lambda v: v=='' or hexstr(64)(v)
position = lambda v: isinstance(v,list) and len(v)==2 and all(num(-10,10)(x) for x in v)
player = one(*PLAYERS)
counters = lambda v: isinstance(v,dict) and len(v)<=24 and all(text(48)(k) and num(0,1000000)(x) for k,x in v.items())
card_fields = dict(zone_ref=text(),id=lambda v:text(80)(v) and bool(v),definition=text(),name=text(),art=art,owner=player,controller=player,holder=player,zone=one('battlefield','graveyard','exile','commander','custom','custom_zone'),position=position,tapped=boolean,face_down=boolean,counters=counters,token=boolean,power=text(),toughness=text())
def deck_back(v):
    presets=('Black','White','Gray','Red','Orange','Yellow','Green','Blue','Purple','Brown')
    return obj(type=one('default','preset','color','image'),color=lambda c:isinstance(c,str) and re.fullmatch(r'#[0-9a-fA-F]{6}',c) is not None,preset=text(16),asset=text(64))(v) and (v['type']!='preset' or v['preset'] in presets) and (v['asset']=='' or (v['type']=='image' and hash_ok(v['asset'])))

def card(v): return isinstance(v,dict) and set(card_fields)<=set(v)<=set(card_fields)|{"face_index","deck_back"} and all(check(v[k]) for k,check in card_fields.items()) and ("face_index" not in v or integer(0,15)(v["face_index"])) and ("deck_back" not in v or deck_back(v["deck_back"])) and (not v['token'] or v['zone'] in ('battlefield','custom','custom_zone'))
def card_update(v): return isinstance(v,dict) and 'id' in v and set(v)<=set(card_fields)|{'face_index','deck_back'} and all((integer(0,15) if k=='face_index' else deck_back if k=='deck_back' else card_fields[k])(x) for k,x in v.items())
counter = obj(id=lambda v:text(80)(v) and bool(v),position=position,value=num(-1000000,1000000),label=text(80))
event = obj(id=text(80),kind=text(32),actor=player,text=text(500))
zone = obj(id=text(80),kind=one('library','deck','graveyard','exile','commander','battlefield','custom','custom_zone'),player=player,name=text(),position=position,size=lambda v:isinstance(v,list) and len(v)==2 and num(20,2304)(v[0]) and num(20,1296)(v[1]),capacity=num(0,5000))
hand = unique(obj(slot=integer(0,999),definition=text(),name=text(),art=art),1000,lambda x:x['slot'])
operations = dict(card_create=card,card_update=card_update,card_remove=obj(id=text(80),destination=one('hand','library','removed'),owner=player,top=boolean),zone_set=zone,hand_public=obj(player=player,cards=hand),counter_set=counter,counter_remove=obj(id=text(80)),counts=obj(player=player,hand=num(0,1000),library=num(0,5000)),life=obj(player=player,delta=num(-1000000,1000000)),end_turn=obj(),order=obj(ids=arr(text(80),500)),history=event)
def operation(v): return isinstance(v,dict) and set(v)=={'kind','data'} and isinstance(v['kind'],str) and v['kind'] in operations and operations[v['kind']](v['data'])
action=obj(action_id=lambda v:text(80)(v) and bool(v),sequence=integer(1,1000000000),actor_player_id=player,action_type=one('batch'),payload=arr(operation,500))
snapshot=obj(cards=mapping(card,500),counters=mapping(counter,500),players=obj(**{p:obj(life=num(-1000000,1000000),hand=num(0,1000),library=num(0,5000)) for p in PLAYERS}),order=arr(text(80),500),turn=obj(number=num(1,1000000000),active=player),history=arr(event,200),zones=mapping(zone,100),hands=obj(**{p:hand for p in PLAYERS}))
_single_definition=obj(id=identifier,name=lambda v:text()(v) and bool(v.strip()),hash=hash_ok,tags=arr(text(48),24))
def definition(v):
    if not isinstance(v,dict): return False
    base={k:x for k,x in v.items() if k!="faces"}
    if not _single_definition(base): return False
    if "faces" not in v: return True
    faces=v["faces"]
    return isinstance(faces,list) and 2<=len(faces)<=16 and all(obj(name=lambda n:text()(n) and bool(n.strip()),hash=hash_ok)(f) for f in faces) and faces[0]["hash"]==v["hash"]
step=integer(1,2)
revision=num(0,1000000000)
def chunk(v):
    if not text(43692)(v): return False
    try: return len(base64.b64decode(v,validate=True))<=32768
    except ValueError: return False
sync=dict(availability=obj(**{k:num(0,8000) for k in ('available','missing','definitions','images')}),manifest=unique(definition,500,lambda x:x['id']),decision=obj(choice=one('sync','placeholders','cancel','start')),begin=obj(),launch=obj(),need=obj(step=step,definitions=unique(identifier,8000),images=unique(hash_ok,8000)),definition=obj(step=step,row=definition),image_begin=obj(step=step,hash=hash_ok,bytes=integer(1,8388608)),chunk=obj(step=step,hash=hash_ok,offset=integer(0,8388608),base64=chunk),ack=obj(offset=num(0,8388608)),sent=obj(step=step),report=obj(step=step,**{k:num(0,8000) for k in ('missing','available','definitions','images','reused')}),error=obj(message=text(200)))
hidden=dict(request=obj(zone=one('hand','library')),deny=obj(reason=text()),close=obj(reason=text()),snapshot=obj(zone=one('hand','library'),cards=unique(card,500,lambda x:x['id'])),move=obj(id=identifier,destination=one('take','hand','battlefield','graveyard','exile','library'),n=integer(1,5001),bottom=boolean))
# Obsolete pre-6D transfer/ack messages are deliberately not relayed.
recovery=dict(seed=obj(match=identifier,secret=hash_ok),hello=obj(match=identifier,nonce=hash_ok,proof=hash_ok,revision=revision),challenge=obj(match=identifier,nonce=hash_ok,proof=hash_ok,revision=revision),proof=obj(match=identifier,nonce=hash_ok,proof=hash_ok,revision=revision),restored=obj(revision=revision),check=obj(revision=revision),action_ack=obj(id=identifier,revision=revision),snapshot=obj(revision=revision,state=snapshot),error=obj(message=text(200)))
tx=dict(summary_request=obj(),prepare=obj(request=identifier,card=card,revealed=boolean),summary=obj(transactions=unique(obj(tx=identifier,id=identifier,side=one('sender','receiver'),phase=one('prepared','committed','acknowledged','rolled_back','unresolved')),256,lambda x:x['tx'])),**{k:obj(id=identifier) for k in ('prepared','commit','committed','rollback')})
families={'card_sync':(sync,{'run':identifier}),'hidden_zone':(hidden,{'request_id':identifier}),'recovery':(recovery,{}),'transfer_tx':(tx,{'tx':identifier})}
def safe_text(n): return lambda v:text(n)(v) and bool(v) and all(ord(x)>=32 and ord(x)!=127 for x in v)
def valid(v,protocol=1,session_id=None):
    if isinstance(v,dict) and 'match_epoch' in v:
        if not hexstr(32)(v['match_epoch']): return False
        if v.get('type') not in ('game','hidden_zone','transfer_tx','table_structure','card_sync') and not (v.get('type')=='recovery' and v.get('kind') not in ('hello','challenge','proof')): return False
        v={k:x for k,x in v.items() if k!='match_epoch'}
    if isinstance(v,dict) and v.get('type')=='battle':
        from battle_protocol import valid as valid_battle
        return protocol==1 and valid_battle(v,session_id)
    if isinstance(v,dict) and v.get("type")=="table_structure":
        from table_protocol import valid as valid_table
        return protocol==1 and valid_table(v,session_id)
    if not isinstance(v,dict) or not isinstance(v.get('type'),str) or not integer(1,65535)(v.get('protocol')) or v['protocol']!=protocol: return False
    kind=v['type']
    common={'type':one(kind),'protocol':integer(1,65535)}
    if 'session_id' in v and (not hexstr(32)(v['session_id']) or (session_id and v['session_id']!=session_id)): return False
    if kind in families:
        variants,extra=families[kind]
        return isinstance(v.get('kind'),str) and v['kind'] in variants and obj(**common,session_id=hexstr(32),kind=one(v['kind']),data=variants[v['kind']],**extra)(v)
    if kind=='game':
        modes={'offer':obj(),'ready':obj(),'resync_request':obj(),'request':action,'commit':action,'resync':snapshot}
        return isinstance(v.get('mode'),str) and v['mode'] in modes and obj(**common,session_id=hexstr(32),mode=one(v['mode']),sequence=integer(0,1000000000),data=modes[v['mode']])(v)
    if kind in ('hello','welcome'):
        fields=dict(app_version=safe_text(24),player_id=one('player_1' if kind=='welcome' else 'player_2'),role=one('host' if kind=='welcome' else 'guest'),display_name=safe_text(48),session_id=hexstr(32))
        if kind=='hello' and 'join_key' in v: fields['join_key']=hexstr(32)
        if 'battle_version' in v: fields.update(battle_version=one(1),reset_pending=boolean)
        return obj(**common,**fields)(v)
    if kind=='ready': return obj(**common,session_id=hexstr(32))(v)
    if kind=='reject': return obj(**common,reason=one('protocol_mismatch','invalid_message'))(v)
    return kind in ('ping','pong','bye') and obj(**common)(v)
def pairs(items):
    result={}
    for key,value in items:
        if key in result: raise ValueError('duplicate key')
        result[key]=value
    return result
def decode(line,protocol=1,session_id=None):
    if not line or len(line)>MAX_FRAME+1 or not line.endswith(b'\n'): return None
    try:
        value=json.loads(line.decode('utf-8'),object_pairs_hook=pairs,parse_constant=lambda _:None)
        if not valid(value,protocol,session_id): return None
        if value['type'] not in ('game','table_structure','battle',*families) and len(line)>2049: return None
        return value
    except (ValueError,TypeError,KeyError,RecursionError,OverflowError): return None

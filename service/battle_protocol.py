"""V0.8.3 safe cosmetics and bilateral rematch envelopes. No private snapshots."""
import relay_protocol as p
from appearance_protocol import background

def back(v): return v=={} or p.deck_back(v)
def cosmetics(v):
    return p.obj(library=back,hand=p.arr(back,1000),piles=lambda x:isinstance(x,dict) and len(x)<=128 and all(p.text(80)(k) and back(b) for k,b in x.items()))(v)
def valid(v,session_id=None):
    if not isinstance(v,dict) or not p.hexstr(32)(v.get('session_id')) or (session_id and v['session_id']!=session_id): return False
    kinds=dict(backs=cosmetics,nickname=p.obj(name=lambda n:p.safe_text(48)(n) and bool(n.strip())),back_need=p.obj(hash=p.hash_ok),back_chunk=p.obj(hash=p.hash_ok,total=p.integer(1,2097152),offset=p.integer(0,2097152),bytes=p.chunk))
    kinds.update(background=background,background_edit=background,background_need=p.obj(hash=p.hash_ok),background_chunk=p.obj(hash=p.hash_ok,total=p.integer(1,8388608),offset=p.integer(0,8388608),bytes=p.chunk),sleeve_request=p.obj(target=lambda x:x=='local' or p.hexstr(32)(x),back=p.deck_back))
    for k in ('request','accept','decline','prepare','committed','go','started','cancel','done','finished','stable'): kinds['reset_'+k]=p.obj(id=p.hexstr(32))
    for k in ('prepared','commit'): kinds['reset_'+k]=p.obj(id=p.hexstr(32),state=p.snapshot)
    kind=v.get('kind')
    if isinstance(kind,str) and kind.startswith('state_'):
        from online_state_protocol import valid as state_valid
        return p.obj(type=p.one('battle'),protocol=p.one(1),session_id=p.hexstr(32),kind=p.one(kind),data=lambda d:state_valid(kind,d))(v)
    return isinstance(kind,str) and kind in kinds and p.obj(type=p.one('battle'),protocol=p.one(1),session_id=p.hexstr(32),kind=p.one(kind),data=kinds[kind])(v)

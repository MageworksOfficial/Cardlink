"""Paired-save transport accepts public metadata only, never private save capsules."""
from relay_protocol import obj,hexstr,hash_ok,snapshot,integer,safe_text,one
identifier=hexstr(32)
HOST_MESSAGES={"state_probe","state_capture","state_save_commit","state_save_done","state_load","state_commit","state_go","state_stable"}
BOTH={"state_cancel","state_save_offer","state_save_accept","state_save_decline"}
def sender_allowed(kind,role):return kind in BOTH or (kind in HOST_MESSAGES)==(role=="host")
def shared(d):
    pair=lambda fn:obj(player_1=fn,player_2=fn)
    return obj(save_state_id=identifier,save_name=safe_text(80),timestamp=safe_text(32),app_version=safe_text(96),table=one('standard'),names=pair(safe_text(48)),fingerprints=pair(hash_ok),roles=pair(hash_ok),public_hash=hash_ok)(d)
def valid(kind,data):
    if not isinstance(data,dict) or not (data.get('epoch')=='' or identifier(data.get('epoch'))):return False
    data={k:v for k,v in data.items() if k!='epoch'}
    simple={"state_save_accept","state_save_decline","state_save_staged","state_save_commit","state_save_committed","state_save_done","state_accept","state_decline","state_commit","state_committed","state_go","state_ack","state_stable"}
    if kind in simple:return obj(id=identifier)(data)
    if kind=='state_cancel':return obj(id=identifier,reason=one('write_failed','missing_pair','pair_mismatch','invalid'))(data)
    if kind=='state_save_offer':return obj(id=identifier,name=safe_text(80))(data)
    if kind=='state_save_ready':return obj(id=identifier,fingerprint=hash_ok,identity=hash_ok)(data)
    if kind in ('state_probe','state_load'):return obj(id=identifier,save_state_id=identifier,shared_hash=hash_ok)(data)
    if kind=='state_info':return obj(id=identifier,fingerprint=lambda v:v=='' or hash_ok(v))(data)
    if kind=='state_capture':return obj(id=identifier,state=snapshot,revision=integer(0,1000000000),shared=shared)(data)
    return False

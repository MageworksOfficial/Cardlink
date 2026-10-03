"""Ephemeral coordination metadata only. Payloads are validated then forwarded, never retained."""
from online_state_protocol import sender_allowed
class SaveRoute:
    NEXT={"state_probe":"state_info","state_info":"state_load","state_load":"state_accept","state_accept":"state_commit","state_commit":"state_committed","state_committed":"state_go","state_go":"state_ack","state_ack":"state_stable","state_save_offer":"state_save_accept","state_save_accept":"state_save_ready","state_save_ready":"state_capture","state_capture":"state_save_staged","state_save_staged":"state_save_commit","state_save_commit":"state_save_committed","state_save_committed":"state_save_done"}
    def __init__(self,enabled=True,peers=None):
        self.enabled=enabled;self.peers=peers if peers is not None else {};self.active=None;self.retired=[];self.requester=""
    def forward(self,role,message):
        kind=message.get('kind','')
        if message.get('type') in ('hello','welcome'):
            if role!=('host' if message['type']=='welcome' else 'guest'): return False
        if message.get('type')!='battle' or not kind.startswith('state_'): return True
        if not self.enabled or not all(self.peers.get(r,0)==3 for r in ('host','guest')) or not sender_allowed(kind,role): return False
        d=message['data'];ident=d['id'];epoch=d['epoch']
        if ident in self.retired: return False
        if self.active is None:
            if kind not in ('state_probe','state_save_offer'): return False
            self.requester=role;self.active=(ident,epoch,self.NEXT[kind]);return True
        current,old_epoch,expected=self.active
        if ident!=current or epoch!=old_epoch: return False
        if kind in ('state_save_accept','state_save_decline') and role==self.requester: return False
        if kind=='state_cancel' or kind=='state_decline' and expected=='state_accept' or kind=='state_save_decline' and expected=='state_save_accept':
            self.finish(ident);return True
        if kind!=expected: return False
        if kind in ('state_save_done','state_stable'): self.finish(ident)
        else: self.active=(ident,epoch,self.NEXT[kind])
        return True
    def finish(self,ident):
        self.retired.append(ident);self.retired=self.retired[-64:];self.active=None

import unittest,json,base64
import relay_protocol as p
class BattleSchemas(unittest.TestCase):
 def frame(self,kind,data):return dict(type='battle',protocol=1,session_id='a'*32,kind=kind,data=data)
 def back(self):return dict(type='color',color='#2468b4',preset='',asset='')
 def test_backs(self):
  v=self.frame('backs',dict(library=self.back(),hand=[self.back(),{}],piles={'pile':self.back()}));self.assertTrue(p.valid(v));v['data']['library']['definition']='private';self.assertFalse(p.valid(v))
 def test_back_limits(self):
  for v in [dict(self.back(),asset='../private'),dict(self.back(),color='<svg>'),dict(self.back(),type='preset',preset='unknown')]:self.assertFalse(p.deck_back(v))
  v=self.frame('backs',dict(library={},hand=[{}]*1001,piles={}));self.assertFalse(p.valid(v))
 def test_reset_envelopes(self):
  for kind in ('request','accept','decline','prepare','committed','go','started','cancel','done','finished','stable'):
   v=self.frame('reset_'+kind,dict(id='b'*32));self.assertTrue(p.valid(v));v['data']['library_order']=[];self.assertFalse(p.valid(v))
 def test_public_snapshot(self):
  s=dict(cards={},counters={},players={x:dict(life=40,hand=0,library=60) for x in p.PLAYERS},order=[],turn=dict(number=1,active='player_1'),history=[],zones={},hands={x:[] for x in p.PLAYERS})
  v=self.frame('reset_commit',dict(id='b'*32,state=s));self.assertTrue(p.valid(v));s['private_library']=[];self.assertFalse(p.valid(v))
 def test_handshake_extension(self):
  v=dict(type='hello',protocol=1,app_version='7.7',player_id='player_2',role='guest',display_name='Vex',session_id='a'*32)
  self.assertTrue(p.valid(v));v.update(battle_version=1,reset_pending=False);self.assertTrue(p.valid(v));v['reset_pending']='true';self.assertFalse(p.valid(v))
 def test_epoch_strictness(self):
  v=dict(type='game',protocol=1,session_id='a'*32,mode='offer',sequence=0,data={},match_epoch='c'*32)
  self.assertTrue(p.valid(v));v['private_deck']=[];self.assertFalse(p.valid(v));v.pop('private_deck');v['match_epoch']='bad';self.assertFalse(p.valid(v))
 def test_custom_chunks(self):
  v=self.frame('back_chunk',dict(hash='a'*64,total=12,offset=0,bytes=base64.b64encode(b'example').decode()));self.assertTrue(p.valid(v));v['data']['total']=2097153;self.assertFalse(p.valid(v));v['data']['total']=12;v['data']['bytes']='not base64!';self.assertFalse(p.valid(v))
 def test_nickname(self):
  self.assertTrue(p.valid(self.frame('nickname',dict(name='Picklenick99'))))
  for n in ('','  ','x'*49,'name\nsecret'): self.assertFalse(p.valid(self.frame('nickname',dict(name=n))))
 def test_public_back_patch(self):
  self.assertTrue(p.card_update(dict(id='card',deck_back=self.back())))
  self.assertFalse(p.card_update(dict(id='card',deck_back=self.back(),library_order=[])))
 def test_duplicate_json_keys(self):
  self.assertIsNone(p.decode(b'{"type":"battle","type":"game"}\n'))
if __name__=='__main__':unittest.main()

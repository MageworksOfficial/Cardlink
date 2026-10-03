import unittest
from save_state_route import SaveRoute
from cardlink_service import Rooms
from online_state_protocol import valid
class RouteTests(unittest.TestCase):
 def setUp(self):self.r=SaveRoute(True,{'host':3,'guest':3})
 def frame(self,kind,id='a'*32,epoch=''):
  return {'type':'battle','kind':'state_'+kind,'data':{'id':id,'epoch':epoch}}
 def step(self,role,kind,**kw):return self.r.forward(role,self.frame(kind,**kw))
 def test_save_flow(self):
  for role,kind in [('host','save_offer'),('guest','save_accept'),('guest','save_ready'),('host','capture'),('guest','save_staged'),('host','save_commit'),('guest','save_committed'),('host','save_done')]:self.assertTrue(self.step(role,kind))
  self.assertIsNone(self.r.active);self.assertFalse(self.step('host','save_offer'))
 def test_load_flow(self):
  for role,kind in [('host','probe'),('guest','info'),('host','load'),('guest','accept'),('host','commit'),('guest','committed'),('host','go'),('guest','ack'),('host','stable')]:self.assertTrue(self.step(role,kind))
  self.assertFalse(self.step('host','commit'))
 def test_decline(self):
  for role,kind in [('host','probe'),('guest','info'),('host','load'),('guest','decline')]:self.assertTrue(self.step(role,kind))
  self.assertIsNone(self.r.active)
 def test_wrong_direction(self):self.assertFalse(self.step('guest','probe'))
 def test_out_of_order(self):self.assertFalse(self.step('host','commit'))
 def test_duplicate_request(self):self.assertTrue(self.step('host','probe'));self.assertFalse(self.step('host','probe'))
 def test_wrong_epoch(self):self.step('host','probe');self.assertFalse(self.step('guest','info',epoch='b'*32))
 def test_wrong_transaction(self):self.step('host','probe');self.assertFalse(self.step('guest','info',id='b'*32))
 def test_cancel(self):self.step('host','probe');self.assertTrue(self.step('guest','cancel'));self.assertIsNone(self.r.active)
 def test_old_relay(self):self.r.enabled=False;self.assertFalse(self.step('host','probe'));self.assertTrue(self.r.forward('host',{'type':'ping'}))
 def test_old_peer(self):self.r.peers.pop('guest');self.assertFalse(self.step('host','probe'))
 def test_storage_metadata_only(self):
  self.step('host','save_offer');self.step('guest','save_accept');self.step('guest','save_ready')
  f=self.frame('capture');f['data']['state']={'secret':'DO_NOT_RETAIN'};self.assertTrue(self.r.forward('host',f));self.assertNotIn('DO_NOT_RETAIN',repr(self.r.__dict__))
 def test_bad_epoch(self):self.assertFalse(valid('state_probe',{'id':'a'*32,'epoch':'bad'}))
 def test_unexpected_epoch_field(self):self.assertFalse(valid('state_probe',{'id':'a'*32,'epoch':'','extra':1}))
 def test_room_capability_authenticated(self):
  rooms=Rooms();r=rooms.request('create',dict(session_id='a'*32,protocol=1,app_version='7.7',addresses=['127.0.0.1'],port=27860))
  self.assertEqual(r['save_state_version'],3)
  cap=rooms.request('save_capability',dict(code=r['code'],token=r['token'],version=3));self.assertEqual(cap['save_peers'],{'host':3})

 def test_resume_clears_peer_capabilities(self):
  rooms=Rooms();r=rooms.request('create',dict(session_id='a'*32,protocol=1,app_version='7.7',addresses=['127.0.0.1'],port=27860))
  rooms.request('save_capability',dict(code=r['code'],token=r['token'],version=3))
  resumed=rooms.request('resume',dict(code=r['code'],token=r['token']))
  self.assertEqual(resumed['save_peers'],{})
 def test_oversize_frame(self):
  import relay_protocol
  self.assertIsNone(relay_protocol.decode(b'x'*(relay_protocol.MAX_FRAME+1)+b'\n'))

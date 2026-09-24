import asyncio
import json
import unittest
from cardlink_service import Rooms,Server,ServiceError
from relay_protocol import decode,MAX_FRAME

class WireTests(unittest.TestCase):
    def frame(self,family,data,**kw):
        v=dict(type=family,protocol=1,session_id='a'*32,**kw,data=data)
        return (json.dumps(v)+'\n').encode()
    def test_reviewed_families(self):
        frames=[self.frame('game',{},mode='offer',sequence=0),self.frame('card_sync',[],kind='manifest',run='run_1'),self.frame('hidden_zone',{'zone':'hand'},kind='request',request_id='request_1'),self.frame('recovery',{'revision':0},kind='check'),self.frame('transfer_tx',{},kind='summary_request',tx='summary')]
        for f in frames:self.assertIsNotNone(decode(f,1,'a'*32))
    def test_nested_private_snapshot_rejected(self):
        self.assertIsNone(decode(self.frame('recovery',{'revision':0,'state':{'library':['private']}},kind='snapshot')))
    def test_arbitrary_game_action_rejected(self):
        self.assertIsNone(decode(self.frame('game',{'payload':'arbitrary'},mode='commit',sequence=1)))
    def test_session_boundary(self):
        self.assertIsNone(decode(self.frame('game',{},mode='offer',sequence=0),1,'b'*32))
    def test_malformed(self):
        for f in (b'[]\n',b'{}\n',b'{\xff}\n',b'{"type":"ping","type":"bye","protocol":1}\n',b'{"type":"ping","protocol":true}\n',b'['*2000+b'\n'):
            self.assertIsNone(decode(f))
    def test_oversized(self): self.assertIsNone(decode(b' '*MAX_FRAME+b'{}\n'))
    def test_invalid_asset_base64(self):
        self.assertIsNone(decode(self.frame('card_sync',dict(step=1,hash='a'*64,offset=0,base64='%%%'),kind='chunk',run='run')))
    def test_valid_asset_chunk(self):
        self.assertIsNotNone(decode(self.frame('card_sync',dict(step=1,hash='a'*64,offset=0,base64='YQ=='),kind='chunk',run='run')))

class InternetRooms(unittest.TestCase):
    def setUp(self):
        self.now=0;self.r=Rooms(ttl=90,clock=lambda:self.now,max_rooms=2)
        self.a=self.r.request('create',dict(protocol=1,app_version='7',session_id='a'*32,addresses=[],port=27860))
        self.b=self.r.request('join',dict(code=self.a['code'],protocol=1,app_version='7'))
    def auth(self,role):return dict(code=self.a['code'],token=(self.a if role=='host' else self.b)['token'])
    def test_resume_keeps_reservation_rotates_transport(self):
        a=self.r.request('resume',self.auth('host'));b=self.r.request('resume',self.auth('guest'))
        self.assertEqual(a['session_id'],b['session_id']);self.assertNotEqual(a['session_id'],self.a['session_id'])
        self.assertEqual(a['mode'],'relay');self.assertEqual(self.r.rooms[a['code']]['host_token'],self.a['token'])
    def test_resume_requires_token(self):
        with self.assertRaises(ServiceError):self.r.request('resume',dict(code=self.a['code'],token='wrong'))
    def test_new_epoch_after_recovery(self):
        a=self.r.request('resume',self.auth('host'))
        for role in ('host','guest'):self.r.request('heartbeat',dict(self.auth(role),connected=True))
        b=self.r.request('resume',self.auth('host'));self.assertNotEqual(a['session_id'],b['session_id'])
    def test_host_crash_cleanup(self):
        self.now=91;self.r.sweep();self.assertEqual(self.r.rooms[self.a['code']]['state'],'expired')
        self.now=152;self.r.sweep();self.assertFalse(self.r.rooms)
    def test_restart_is_ephemeral(self):self.assertFalse(Rooms().rooms)
    def test_build_mismatch(self):
        c=self.r.request('create',dict(protocol=1,app_version='7',session_id='c'*32,addresses=[],port=27860))
        with self.assertRaises(ServiceError):self.r.request('join',dict(code=c['code'],protocol=1,app_version='6D'))
    def test_health_no_rooms(self):
        health=self.r.request('health',{});self.assertNotIn(self.a['code'],str(health));self.assertTrue(health['gameplay_relay'])
    def test_protocol_rejected_at_create(self):
        with self.assertRaises(ServiceError):self.r.request('create',dict(protocol=2,app_version='7',session_id='a'*32,addresses=[],port=27860))

class LiveRelay(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.r=Rooms();self.s=Server(self.r)
        self.server=await asyncio.start_server(self.s.relay,'127.0.0.1',0,limit=MAX_FRAME+2)
        self.port=self.server.sockets[0].getsockname()[1]
        self.a=self.r.request('create',dict(protocol=1,app_version='7',session_id='a'*32,addresses=[],port=27860))
        self.b=self.r.request('join',dict(code=self.a['code'],protocol=1,app_version='7'))
        self.r.request('relay',dict(code=self.a['code'],token=self.a['token']))
        self.ends=[]
        for identity in (self.a,self.b):
            reader,writer=await asyncio.open_connection('127.0.0.1',self.port)
            writer.write((json.dumps(dict(code=identity['code'],token=identity['token']))+'\n').encode());await writer.drain()
            self.ends.append((reader,writer))
        for reader,_ in self.ends:self.assertEqual(await asyncio.wait_for(reader.readline(),3),b'{"paired":true}\n')
    async def asyncTearDown(self):
        for _,writer in self.ends:writer.close();await writer.wait_closed()
        self.server.close();await self.server.wait_closed();await asyncio.sleep(.05)
    async def test_forward_game(self):
        f=b'{"type":"game","protocol":1,"session_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","mode":"offer","sequence":0,"data":{}}\n'
        self.ends[0][1].write(f);await self.ends[0][1].drain()
        self.assertEqual(await asyncio.wait_for(self.ends[1][0].readline(),2),f)
    async def test_malformed_disconnects(self):
        self.ends[0][1].write(b'{"type":"game","arbitrary":"payload"}\n');await self.ends[0][1].drain()
        self.assertEqual(await asyncio.wait_for(self.ends[1][0].readline(),2),b'')
    async def test_oversized_disconnects(self):
        self.ends[0][1].write(b'x'*(MAX_FRAME+10)+b'\n');await self.ends[0][1].drain()
        self.assertEqual(await asyncio.wait_for(self.ends[1][0].readline(),2),b'')
    async def test_traffic_limit(self):
        self.s.traffic_limit=1
        self.ends[0][1].write(b'{"type":"ping","protocol":1}\n');await self.ends[0][1].drain()
        self.assertEqual(await asyncio.wait_for(self.ends[1][0].readline(),2),b'')

if __name__=='__main__':unittest.main()

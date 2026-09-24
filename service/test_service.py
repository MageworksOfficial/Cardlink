import unittest
from cardlink_service import Rooms, ServiceError


class RoomTests(unittest.TestCase):
    def setUp(self):
        self.now = 0
        self.service = Rooms(clock=lambda: self.now)
        self.data = dict(session_id='a'*32, protocol=1, app_version='6F', addresses=['127.0.0.1'], port=27860)

    def create(self):
        return self.service.request('create', self.data)

    def error(self, expected, action, data):
        with self.assertRaises(ServiceError) as caught:
            self.service.request(action, data)
        self.assertEqual(caught.exception.result['error'], expected)

    def test_creation_and_code(self):
        a, b = self.create(), self.create()
        self.assertRegex(a['code'], r'^[A-Z]{4}-[0-9]{4}$')
        self.assertNotEqual(a['code'], b['code'])
        self.assertEqual(a['state'], 'waiting')
        self.assertEqual(len(a['token']), 32)

    def test_lookup_missing(self):
        self.error('room_not_found', 'lookup', dict(code='ABCD-9999'))

    def test_lookup(self):
        a=self.create()
        found=self.service.request('lookup', dict(code=a['code']))
        self.assertEqual(found['protocol'], 1)
        self.assertNotIn('token', found)

    def test_expiry(self):
        a=self.create(); self.now=21
        self.error('host_offline', 'lookup', dict(code=a['code']))
        self.now=82; self.service.sweep()
        self.assertFalse(self.service.rooms)

    def test_heartbeat(self):
        a=self.create(); self.now=15
        self.service.request('heartbeat', dict(code=a['code'], token=a['token'], connected=False))
        self.now=30
        self.assertEqual(self.service.request('lookup', dict(code=a['code']))['state'], 'waiting')

    def test_compatible_join_and_full(self):
        a=self.create(); data=dict(code=a['code'],protocol=1,app_version='6F')
        b=self.service.request('join',data)
        self.assertEqual(a['join_key'],b['join_key'])
        self.assertNotEqual(a['token'],b['token'])
        self.error('room_full','join',data)

    def test_incompatible(self):
        a=self.create()
        self.error('incompatible','join',dict(code=a['code'],protocol=2,app_version='next'))
        self.assertFalse(self.service.rooms[a['code']]['guest_token'])

    def test_guest_disappearance(self):
        a=self.create(); self.service.request('join',dict(code=a['code'],protocol=1,app_version='6F'))
        self.now=15; self.service.request('heartbeat',dict(code=a['code'],token=a['token'],connected=False))
        self.now=21; self.error('host_offline','lookup',dict(code=a['code']))

    def test_close(self):
        a=self.create(); self.service.request('close',dict(code=a['code'],token=a['token']))
        self.error('room_closed','lookup',dict(code=a['code']))

    def test_capability_required(self):
        a=self.create()
        self.error('unauthorized','close',dict(code=a['code'],token='incorrect'))

    def test_private_data_rejected(self):
        for field in ('hand', 'deck', 'library', 'match_history','image'):
            self.error('invalid_request','create',dict(self.data,**{field:'PRIVATE'}))
        self.assertFalse(self.service.rooms)

    def test_relay_negotiation(self):
        a=self.create(); result=self.service.request('relay',dict(code=a['code'],token=a['token']))
        self.assertEqual(result['mode'],'relay')

    def test_no_relay(self):
        self.service.relay_port=0; a=self.create()
        self.error('relay_unavailable','relay',dict(code=a['code'],token=a['token']))

    def test_invalid_endpoints(self):
        for address in ('not-an-ip','0.0.0.0','224.0.0.1'):
            self.error('invalid_request','create',dict(self.data,addresses=[address]))

    def test_health(self):
        self.assertTrue(self.service.request('health',{})['relay_available'])


if __name__=='__main__':
    unittest.main()

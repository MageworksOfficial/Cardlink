import unittest
import relay_protocol as p
class OnlineStateTests(unittest.TestCase):
 def frame(self,kind,data):return dict(type="battle",protocol=1,session_id="a"*32,kind=kind,data={"epoch":"",**data})
 def test_simple(self):self.assertTrue(p.valid(self.frame("state_save_offer",{"id":"b"*32,"name":"Friday"})))
 def test_plaintext_private_rejected(self):self.assertFalse(p.valid(self.frame("state_save_offer",{"id":"b"*32,"name":"Friday","hand":["secret"]})))
 def test_old_capsule_traffic(self):self.assertFalse(p.valid(self.frame("state_data",{"id":"b"*32,"capsule":{}})))
 def test_invalid_id(self):self.assertFalse(p.valid(self.frame("state_save_offer",{"id":"bad","name":"Friday"})))
 def test_oversized(self):self.assertFalse(p.valid(self.frame("state_save_offer",{"id":"b"*32,"name":"a"*81})))
 def test_extra_fields(self):self.assertFalse(p.valid(self.frame("state_save_offer",{"id":"b"*32,"name":"Friday","extra":1})))
 def test_version(self):
  f=self.frame("state_save_offer",{"id":"b"*32,"name":"Friday"});f["protocol"]=2;self.assertFalse(p.valid(f))
 def test_unknown(self):self.assertFalse(p.valid(self.frame("state_unrestricted_snapshot",{"id":"b"*32})))

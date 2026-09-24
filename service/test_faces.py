import unittest
from relay_protocol import definition,card_update,card,card_fields

class FaceSchemas(unittest.TestCase):
    def base(self): return dict(id='example',name='Front',hash='a'*64,tags=[])
    def test_old_definition(self): self.assertTrue(definition(self.base()))
    def test_faces(self):
        d=self.base();d['faces']=[dict(name='Front',hash='a'*64),dict(name='Back',hash='b'*64)]
        self.assertTrue(definition(d))
        d['faces'][1]['image_path']='/private/path'
        self.assertFalse(definition(d))
    def test_bad_definitions(self):
        for d in [None,{},dict(self.base(),faces=[]),dict(self.base(),faces=[dict(name='Front',hash='a'*64)]),dict(self.base(),faces=[dict(name='Wrong',hash='b'*64)]*2)]:self.assertFalse(definition(d))
    def test_face_patch(self):
        self.assertTrue(card_update(dict(id='instance',face_index=1)))
        for n in [-1,16,1.5,True]:self.assertFalse(card_update(dict(id='instance',face_index=n)))
        self.assertFalse(card_update(dict(id='instance',faces=[dict(name='Private')])) )
    def test_old_and_new_card(self):
        d=dict(zone_ref='',id='i',definition='d',name='Front',art='a'*64,owner='player_1',controller='player_2',holder='player_1',zone='battlefield',position=[0,0],tapped=True,face_down=False,counters={},token=False,power='',toughness='')
        self.assertTrue(card(d));d['face_index']=1;self.assertTrue(card(d));d['private_library']=[];self.assertFalse(card(d))

if __name__=='__main__': unittest.main()

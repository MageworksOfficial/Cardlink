import unittest,copy,json
import relay_protocol as relay
from table_protocol import table,valid
class TableTests(unittest.TestCase):
    def fixture(self):
        row=dict(id='b'*32,kind='shared_deck',name='Draw',owner='table',visibility='private',position=[0,0],size=[100,140],hidden=False,locked=False,rotation=0,opacity=1,asset='',back='',linked_pile='',text='')
        return dict(format=1,id='a'*32,name='Table',description='',author='',dimensions=[3200,2000],components=[row])
    def frame(self):return dict(type='table_structure',protocol=1,session_id='c'*32,kind='table',data={'table':self.fixture()})
    def test_roundtrip(self):
        f=self.frame();self.assertTrue(valid(f));self.assertEqual(relay.decode((json.dumps(f)+'\n').encode()),f)
    def test_private_extra_rejected(self):
        f=self.frame();f['data']['library_order']=['private'];self.assertFalse(valid(f))
    def test_code_and_path_rejected(self):
        d=self.fixture();d['components'][0]['script']='evil';self.assertFalse(table(d))
        d=self.fixture();d['components'][0]['asset']='../../secret';self.assertFalse(table(d))
    def test_limits(self):
        for value in [float('inf'),float('nan'),1000000,True]:
            d=self.fixture();d['components'][0]['position'][0]=value;self.assertFalse(table(d))
        d=self.fixture();d['components']*=129;self.assertFalse(table(d))
    def test_version_owner_duplicates(self):
        d=self.fixture();d['format']=2;self.assertFalse(table(d))
        d=self.fixture();d['components'][0]['owner']='player_1';self.assertFalse(table(d))
        d=self.fixture();d['components']*=2;self.assertFalse(table(d))
    def test_only_needed_image_envelope(self):
        f=self.frame();f.update(kind='need',data={'hash':'a'*64});self.assertTrue(valid(f));f['data']['path']='/etc/passwd';self.assertFalse(valid(f))
    def test_draw_has_no_identity(self):
        f=self.frame();f.update(kind='draw',data={'id':'b'*32,'player':'player_2'});self.assertTrue(valid(f));f['data']['card_name']='secret';self.assertFalse(valid(f))
if __name__=='__main__':unittest.main()

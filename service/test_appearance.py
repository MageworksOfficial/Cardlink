import unittest,copy
import relay_protocol as p
from appearance_protocol import background
class Appearance(unittest.TestCase):
 def config(self): return dict(type='image',color='#123456',asset='a'*64,position=[-100,50],size=[6000,4000],rotation=270,opacity=0,locked=True)
 def frame(self,k,d): return dict(type='battle',protocol=1,session_id='b'*32,kind=k,data=d)
 def test_background(self):
  self.assertTrue(background(self.config()));self.assertTrue(p.valid(self.frame('background',self.config())))
 def test_private_rejection(self):
  for key in ('cards','hand','library_order','path'):
   v=self.config();v[key]=[];self.assertFalse(background(v))
 def test_bad_values(self):
  for key,value in [('asset','../../secret'),('size',[float('inf'),40]),('rotation',361),('opacity',-1),('locked',1),('color','url(file)')]:
   v=self.config();v[key]=value;self.assertFalse(background(v))
 def test_request(self):
  v=self.frame('sleeve_request',dict(target='local',back=dict(type='color',color='#ffffff',preset='',asset='')));self.assertTrue(p.valid(v));v['data']['save']=True;self.assertFalse(p.valid(v))
 def test_chunk_bounds(self):
  v=self.frame('background_chunk',dict(hash='a'*64,total=8388608,offset=0,bytes='YWJj'));self.assertTrue(p.valid(v));v['data']['total']+=1;self.assertFalse(p.valid(v))
 def test_template_extension(self):
  import table_protocol as t
  v=dict(format=1,id='a'*32,name='Table',description='',author='',dimensions=[3200,2000],components=[],background=self.config());self.assertTrue(t.table(v));v['background']['private']=[];self.assertFalse(t.table(v))
if __name__=='__main__': unittest.main()

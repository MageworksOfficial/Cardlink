"""Strict public-only V0.8.4 appearance schemas."""
import re
import table_protocol as t

def background(v):
    return (isinstance(v,dict) and set(v)=={'type','color','asset','position','size','rotation','opacity','locked'}
        and v['type'] in ('default','color','image') and isinstance(v['color'],str) and re.fullmatch(r'#[0-9a-fA-F]{6}',v['color']) is not None
        and t.hx(v['asset'],64,True) and (v['type']!='image' or bool(v['asset'])) and t.pair(v['position'],-20000,20000)
        and t.pair(v['size'],40,20000) and t.number(v['rotation'],-360,360) and t.number(v['opacity'],0,1) and type(v['locked']) is bool)

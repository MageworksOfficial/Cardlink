import asyncio
import copy
import json
from pathlib import Path
import tempfile
import unittest
from update_manifest import UpdateManifest, validate, version
from cardlink_service import Server, Rooms

class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.directory=tempfile.TemporaryDirectory();self.addCleanup(self.directory.cleanup)
        self.path=Path(self.directory.name)/"manifest.json"
        self.data=json.loads(Path(__file__).with_name("update_manifest.json").read_text())
        self.path.write_text(json.dumps(self.data))
    def test_prepared_manifest(self):
        self.assertEqual(validate(self.data)["latest_version"],"0.8.5.1")
        self.assertEqual(self.data["assets"],{}) # never mislabel the older 7.8.1 archive
    def test_version_order(self):
        self.assertGreater(version("0.8.5.1"),version("0.8.5"))
        self.assertGreater(version("0.8.10"),version("0.8.9"))
    def test_beta_channel(self):
        self.assertLess(version("0.8.5.1-beta"),version("0.8.5.1"))
        self.assertGreater(version("0.8.5.1-beta"),version("0.8.5"))
        with self.assertRaises(ValueError):version("0.8.5.1-evil")
    def test_bad_fields(self):
        for key,value in [('latest_version','bad'),('minimum_online_version','99.0.0'),('update_level','panic'),('release_url','https://evil.invalid'),('server_directory_url','http://directory.invalid')]:
            with self.subTest(key=key),self.assertRaises(ValueError):validate(dict(self.data,**{key:value}))
    def test_asset_validation(self):
        asset={'url':'https://github.com/MageworksOfficial/Cardlink/releases/download/test/sample.zip','sha256':'a'*64,'size':123}
        data=dict(self.data,assets={'windows-x86_64':asset});validate(data)
        for key,value in [('url','file:///tmp/payload'),('sha256','bad'),('size',0),('size',True)]:
            bad=copy.deepcopy(data);bad['assets']['windows-x86_64'][key]=value
            with self.subTest(key=key),self.assertRaises(ValueError):validate(bad)
    def test_cache_and_reload(self):
        clock=[0];source=UpdateManifest(self.path,lambda:clock[0]);self.assertEqual(source.get(),validate(self.data))
        self.path.write_text('{');self.assertEqual(source.get(),validate(self.data))
        clock[0]=11;self.assertEqual(source.get(),{'error':'update_status_unavailable'})
    def test_missing_oversized(self):
        self.path.unlink();self.assertIn('error',UpdateManifest(self.path).get())
        self.path.write_bytes(b' '*70000);self.assertIn('error',UpdateManifest(self.path).get())
    def test_metadata_only(self):
        self.data['private_cards']=['hidden'];self.assertNotIn('private_cards',validate(self.data))
    def test_optional_directory(self):
        self.data['server_directory_url']='https://directory.invalid/v1/servers'
        self.assertEqual(validate(self.data)['server_directory_url'],self.data['server_directory_url'])

class HTTPTests(unittest.IsolatedAsyncioTestCase):
    async def request(self,server,head,body=b''):
        listener=await asyncio.start_server(server.http,'127.0.0.1',0)
        try:
            reader,writer=await asyncio.open_connection('127.0.0.1',listener.sockets[0].getsockname()[1])
            writer.write(head+body);await writer.drain();response=await asyncio.wait_for(reader.read(),3)
            writer.close();await writer.wait_closed()
            return json.loads(response.split(b'\r\n\r\n',1)[1])
        finally:listener.close();await listener.wait_closed()
    async def test_update_works_without_rooms(self):
        response=await self.request(Server(None),b'GET /v1/update HTTP/1.1\r\nHost: localhost\r\n\r\n')
        self.assertEqual(response['latest_version'],'0.8.5.1')
        self.assertNotIn('room',response)
    async def test_invalid_manifest_does_not_break_health(self):
        server=Server(Rooms(),update_manifest='/missing-update-manifest.json')
        update=await self.request(server,b'GET /v1/update HTTP/1.1\r\nHost: localhost\r\n\r\n')
        self.assertEqual(update,{'error':'update_status_unavailable'})
        health=await self.request(server,b'POST /v1/health HTTP/1.1\r\nContent-Length: 2\r\n\r\n',b'{}')
        self.assertNotIn('error',health)
    async def test_update_no_gameplay_body(self):
        result=await self.request(Server(None),b'GET /v1/update HTTP/1.1\r\nContent-Length: 2\r\n\r\n',b'{}')
        self.assertEqual(result,{'error':'invalid_request'})

"""Ephemeral rendezvous and validated, non-persistent gameplay relay. Python standard library."""
from update_manifest import UpdateManifest
import argparse
import os
import logging
import signal
from relay_protocol import decode, MAX_FRAME
from save_state_route import SaveRoute
import asyncio
import collections
import ipaddress
import json
import secrets
import ssl
import time


class ServiceError(Exception):
    def __init__(self, code, **details):
        self.result = dict(error=code, **details)


def exact(data, fields):
    if not isinstance(data, dict) or set(data) != set(fields.split()):
        raise ServiceError('invalid_request')


def version(data):
    if type(data['protocol']) is not int or not 1 <= data['protocol'] <= 65535:
        raise ServiceError('invalid_request')
    if not isinstance(data['app_version'], str) or not 1 <= len(data['app_version']) <= 24:
        raise ServiceError('invalid_request')


class Rooms:
    def __init__(self, relay_port=8788, tls=False, ttl=20, clock=time.monotonic, protocol=1, max_rooms=200, max_age=14400, relay_host="", save_state_version=3):
        self.protocol = protocol
        self.save_state_version = save_state_version
        self.max_rooms = max_rooms
        self.max_age = max_age
        self.relay_host = relay_host
        self.rooms = {}
        self.clock = clock
        self.ttl = ttl
        self.relay_port = relay_port
        self.tls = tls

    def sweep(self):
        now = self.clock()
        for code, room in list(self.rooms.items()):
            if room['state'] not in ('closed', 'expired'):
                if now - room['host_seen'] > self.ttl or now - room['born'] > self.max_age or (room['guest_token'] and now - room['guest_seen'] > self.ttl):
                    room['state'] = 'expired'
                    room['ended'] = now
            elif now - room['ended'] > 60:
                del self.rooms[code]

    def get(self, code):
        self.sweep()
        if not isinstance(code, str) or len(code) != 9 or code[4] != '-' or not code[:4].isalpha() or not code[5:].isdigit():
            raise ServiceError('room_not_found')
        room = self.rooms.get(code)
        if room is None:
            raise ServiceError('room_not_found')
        if room['state'] in ('closed', 'expired'):
            raise ServiceError('host_offline' if room['state'] == 'expired' else 'room_closed')
        return room

    def authenticate(self, data):
        room = self.get(data['code'])
        token = data['token']
        if not isinstance(token, str) or not token:
            raise ServiceError('unauthorized')
        role = 'host' if secrets.compare_digest(token, room['host_token']) else 'guest' if secrets.compare_digest(token, room['guest_token']) else ''
        if not role:
            raise ServiceError('unauthorized')
        return room, role

    def view(self, room):
        return {key: room[key] for key in ('code', 'session_id', 'protocol', 'app_version', 'state', 'mode', 'addresses', 'port')} | {
            'guest_joined': bool(room['guest_token']), 'relay_port': self.relay_port, 'relay_tls': self.tls, 'relay_host': self.relay_host, 'save_state_version': self.save_state_version, 'save_peers': room.get('save_peers',{})}

    def request(self, action, data):
        self.sweep()
        if action == 'health':
            exact(data, '')
            return dict(service='cardlink-rendezvous', api=1, relay_available=bool(self.relay_port), relay_tls=self.tls, relay_port=self.relay_port, relay_host=self.relay_host, protocol=self.protocol, gameplay_relay=True)
        if action == 'create':
            exact(data, 'session_id protocol app_version addresses port')
            version(data)
            if data['protocol'] != self.protocol:
                raise ServiceError('incompatible', protocol=self.protocol)
            if len(self.rooms) >= self.max_rooms:
                raise ServiceError('service_busy')
            try:
                if not isinstance(data['session_id'], str) or len(data['session_id']) != 32:
                    raise ValueError()
                int(data['session_id'], 16)
                if type(data['port']) is not int or not 1024 <= data['port'] <= 65535:
                    raise ValueError()
                if not isinstance(data['addresses'], list) or len(data['addresses']) > 8:
                    raise ValueError()
                for address in data['addresses']:
                    ip = ipaddress.ip_address(address)
                    if ip.is_unspecified or ip.is_multicast:
                        raise ValueError()
            except (ValueError, TypeError):
                raise ServiceError('invalid_request')
            code = ''
            while not code or code in self.rooms:
                code = ''.join(secrets.choice('ABCDEFGHJKLMNPQRSTUVWXYZ') for _ in range(4)) + '-' + ''.join(secrets.choice('0123456789') for _ in range(4))
            room = dict(data, code=code, state='waiting', mode='direct', host_token=secrets.token_hex(16), guest_token='', join_key=secrets.token_hex(16), born=self.clock(), host_seen=self.clock(), guest_seen=self.clock(), connected=set())
            self.rooms[code] = room
            return self.view(room) | dict(token=room['host_token'], join_key=room['join_key'])
        if action == 'save_capability':
            exact(data, 'code token version')
            room, role = self.authenticate(data)
            if self.save_state_version!=3 or type(data['version']) is not int or data['version']!=3: raise ServiceError('invalid_request')
            room.setdefault('save_peers',{})[role]=3
            return self.view(room)
        if action == 'lookup':
            exact(data, 'code')
            room = self.get(data['code'])
            return {key: room[key] for key in ('code', 'protocol', 'app_version', 'state')}
        if action == 'join':
            exact(data, 'code protocol app_version')
            version(data)
            room = self.get(data['code'])
            if data['protocol'] != room['protocol'] or data['app_version'] != room['app_version']:
                raise ServiceError('incompatible', protocol=room['protocol'], app_version=room['app_version'])
            if room['guest_token']:
                raise ServiceError('room_full')
            room.update(guest_token=secrets.token_hex(16), guest_seen=self.clock(), state='connecting')
            return self.view(room) | dict(token=room['guest_token'], join_key=room['join_key'])
        if action in ('heartbeat', 'relay', 'close', 'resume'):
            exact(data, 'code token connected' if action == 'heartbeat' else 'code token')
            room, role = self.authenticate(data)
            if action == 'resume':
                if not room.get('recovering', False):
                    room.update(session_id=secrets.token_hex(16), mode='relay', state='connecting', recovering=True)
                    room['connected'].clear()
                    room.setdefault('save_peers',{}).clear()
                room[role + '_seen'] = self.clock()
                return self.view(room)
            if action == 'close':
                room.update(state='closed', ended=self.clock())
                return dict(closed=True)
            if action == 'relay':
                if not self.relay_port:
                    raise ServiceError('relay_unavailable')
                if room['state'] == 'full':
                    raise ServiceError('already_connected')
                room['mode'] = 'relay'
            if action == 'heartbeat':
                if type(data['connected']) is not bool:
                    raise ServiceError('invalid_request')
                room[role + '_seen'] = self.clock()
                if data['connected']:
                    room['connected'].add(role)
                else:
                    room['connected'].discard(role)
                if len(room['connected']) == 2:
                    room['state'] = 'full'
                    room['recovering'] = False
            return self.view(room)
        raise ServiceError('invalid_request')


class Server:
    def __init__(self, rooms, traffic_limit=1073741824, idle_timeout=30, update_manifest=None):
        self.rooms = rooms
        self.updates = UpdateManifest(update_manifest)
        self.traffic_limit = traffic_limit
        self.idle_timeout = idle_timeout
        self.relay_active = 0
        self.rates = {}
        self.pairs = {}
        self.relay_ready = {}
        self.save_routes = {}
        self.active = 0

    async def http(self, reader, writer):
        self.active += 1
        try:
            if self.active > 256:
                writer.close()
                return
            head = await asyncio.wait_for(reader.readuntil(b'\r\n\r\n'), 5)
            if len(head) > 4096:
                writer.close()
                return
            lines = head.decode('ascii').split('\r\n')
            method, path, _ = lines[0].split()
            headers = dict(line.split(':', 1) for line in lines[1:] if ':' in line)
            headers = {k.lower(): v.strip() for k, v in headers.items()}
            length = int(headers.get('content-length', '0'))
            update_request = method == 'GET' and path == '/v1/update' and length == 0
            if (not update_request and (method != 'POST' or not path.startswith('/v1/'))) or not 0 <= length <= 4096 or 'transfer-encoding' in headers:
                raise ServiceError('invalid_request')
            now = time.monotonic()
            ip = writer.get_extra_info('peername')[0]
            if ip not in self.rates and len(self.rates) >= 4096:
                self.rates = {key: values for key, values in self.rates.items() if values and now - values[-1] < 60}
                if len(self.rates) >= 4096:
                    raise ServiceError('service_busy')
            rate = self.rates.setdefault(ip, collections.deque())
            while rate and now - rate[0] > 60:
                rate.popleft()
            if len(rate) >= 180:
                raise ServiceError('service_busy')
            rate.append(now)
            if update_request:
                result = self.updates.get()
            else:
                data = json.loads(await asyncio.wait_for(reader.readexactly(length), 5))
                action = path[4:]
                previous = self.rooms.rooms.get(data.get('code'), {}).get('session_id') if isinstance(data,dict) else None
                result = self.rooms.request(action, data)
                if action == 'resume' and result.get('session_id') != previous:
                    old_pair = self.pairs.pop(data['code'], {})
                    self.save_routes.pop(data['code'], None)
                    self.relay_ready.pop(data['code'], None)
                    for _, partner in list(old_pair.values()): partner.close()
                if action in ('create','join','close','resume'):
                    logging.info('room %s', action)
        except ServiceError as exc:
            result = exc.result
        except (ValueError, TypeError, UnicodeError, asyncio.IncompleteReadError, asyncio.LimitOverrunError, TimeoutError, RecursionError, ConnectionError):
            result = dict(error='invalid_request')
        finally:
            self.active -= 1
        try:
            body = json.dumps(result).encode()
            writer.write(b'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: ' + str(len(body)).encode() + b'\r\n\r\n' + body)
            await writer.drain()
        except (ConnectionError, UnboundLocalError):
            pass
        finally:
            writer.close()

    async def relay(self, reader, writer):
        code, role, pair = '', '', None
        self.relay_active += 1
        try:
            if self.relay_active > self.rooms.max_rooms * 2 + 16: return
            line = await asyncio.wait_for(reader.readline(), 8)
            if len(line) > 256:
                return
            data = json.loads(line)
            if data == {'probe': True}:
                writer.write((json.dumps({'relay': True, 'protocol': self.rooms.protocol})+'\n').encode())
                await asyncio.wait_for(writer.drain(), 3)
                return
            exact(data, 'code token')
            room, role = self.rooms.authenticate(data)
            if room['mode'] != 'relay':
                return
            code = room['code']
            transport = room['session_id']
            pair = self.pairs.setdefault(code, {})
            save_route = self.save_routes.setdefault(code, SaveRoute(self.rooms.save_state_version==3,room.get("save_peers",{})))
            if role in pair:
                return
            pair[role] = (reader, writer)
            for _ in range(100):
                if len(pair) == 2:
                    break
                await asyncio.sleep(.1)
                self.rooms.get(code)
            if len(pair) != 2:
                return
            writer.write(b'{"paired":true}\n')
            await writer.drain()
            ready = self.relay_ready.setdefault(code, set())
            ready.add(role)
            for _ in range(500):
                if len(ready) == 2:
                    break
                await asyncio.sleep(.01)
            if len(ready) != 2:
                return
            other = pair['guest' if role == 'host' else 'host'][1]
            logging.info('relay paired')
            traffic = 0
            while True:
                line = await asyncio.wait_for(reader.readline(), self.idle_timeout)
                if self.rooms.get(code)['session_id'] != transport: break
                message = decode(line, room['protocol'], transport)
                if message is None: break
                traffic += len(line)
                if traffic > self.traffic_limit: break
                if not save_route.forward(role,message): continue
                other.write(line)
                await asyncio.wait_for(other.drain(), 10)
        except (ServiceError, ValueError, TypeError, KeyError, ConnectionError, TimeoutError, RecursionError):
            pass
        finally:
            self.relay_active -= 1
            writer.close()
            if pair and pair.get(role, (None, None))[1] is writer:
                for _, partner in list(pair.values()): partner.close()
                if self.pairs.get(code) is pair:
                    self.pairs.pop(code, None)
                    self.save_routes.pop(code, None)
                    self.relay_ready.pop(code, None)
                logging.info('relay disconnected')

    async def sweep(self):
        while True:
            await asyncio.sleep(1)
            self.rooms.sweep()
            for code, pair in list(self.pairs.items()):
                room = self.rooms.rooms.get(code)
                if not room or room['state'] in ('closed', 'expired'):
                    for _, writer in list(pair.values()):
                        writer.close()


async def main(args):
    context = None
    if args.cert and args.key:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(args.cert, args.key)
        if hasattr(signal, 'SIGHUP'):
            def reload_certificate():
                try:
                    context.load_cert_chain(args.cert, args.key)
                    logging.info('TLS certificate reloaded')
                except (OSError, ssl.SSLError):
                    logging.error('TLS certificate reload failed; retaining current context')
            asyncio.get_running_loop().add_signal_handler(signal.SIGHUP, reload_certificate)
    if args.bind not in ('127.0.0.1', '::1') and context is None:
        raise SystemExit('Public binding requires --cert and --key. Plaintext development is loopback-only.')
    rooms = Rooms(0 if args.no_relay else args.relay_port, bool(context), ttl=args.ttl, protocol=args.protocol, max_rooms=args.max_rooms, max_age=args.max_age, relay_host=args.relay_host)
    service = Server(rooms, args.traffic_limit, args.idle_timeout, args.update_manifest)
    tls_timeouts = {'ssl_handshake_timeout': 10, 'ssl_shutdown_timeout': 5} if context else {}
    servers = [await asyncio.start_server(service.http, args.bind, args.port, ssl=context, limit=8192, backlog=64, **tls_timeouts)]
    if not args.no_relay:
        servers.append(await asyncio.start_server(service.relay, args.bind, args.relay_port, ssl=context, limit=MAX_FRAME+2, backlog=64, **tls_timeouts))
    print('CardLink service ready', flush=True)
    await asyncio.gather(service.sweep(), *(server.serve_forever() for server in servers))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--update-manifest', default=os.getenv('CARDLINK_UPDATE_MANIFEST'))
    parser.add_argument('--bind', default=os.getenv('CARDLINK_BIND','127.0.0.1'))
    parser.add_argument('--port', type=int, default=int(os.getenv("CARDLINK_PORT","8787")))
    parser.add_argument('--relay-port', type=int, default=int(os.getenv("CARDLINK_RELAY_PORT","8788")))
    parser.add_argument('--no-relay', action='store_true')
    parser.add_argument('--cert', default=os.getenv('CARDLINK_CERT'))
    parser.add_argument('--key', default=os.getenv('CARDLINK_KEY'))
    parser.add_argument('--relay-host',default=os.getenv('CARDLINK_RELAY_HOST',''))
    parser.add_argument('--protocol',type=int,default=int(os.getenv('CARDLINK_PROTOCOL','1')))
    parser.add_argument('--ttl',type=int,default=int(os.getenv('CARDLINK_ROOM_TTL','90')))
    parser.add_argument('--max-age',type=int,default=int(os.getenv('CARDLINK_ROOM_MAX_AGE','14400')))
    parser.add_argument('--max-rooms',type=int,default=int(os.getenv('CARDLINK_MAX_ROOMS','32')))
    parser.add_argument('--traffic-limit',type=int,default=int(os.getenv('CARDLINK_TRAFFIC_LIMIT','1073741824')))
    parser.add_argument('--idle-timeout',type=int,default=int(os.getenv('CARDLINK_IDLE_TIMEOUT','30')))
    logging.basicConfig(level=logging.INFO,format='%(asctime)s %(message)s')
    asyncio.run(main(parser.parse_args()))


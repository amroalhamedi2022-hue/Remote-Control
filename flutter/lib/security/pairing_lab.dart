/// v0.5 experimental signed pairing and view-only MJPEG LAN preview.
/// All screen sharing requires an extra LOCAL host approval (SHARE on Node agent).
/// No remote input, files, clipboard or unattended access is authorized.
/// The bespoke handshake MUST be replaced/audited before product release.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const pairingPort = 43829;
const _protocol = 'liquidremote.pair.v1';
const _maxFrameBytes = 8192;
const _timeout = Duration(seconds: 120);
const _edSpki = <int>[0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00];
const _xSpki = <int>[0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x6e, 0x03, 0x21, 0x00];

String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
List<int> _unb64(String str) => base64Url.decode(base64Url.normalize(str));
String _hex(List<int> bytes) => bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
List<int> _rand(int len) {
  final rng = Random.secure();
  return List<int>.generate(len, (_) => rng.nextInt(256));
}
Future<List<int>> _sha(List<int> data) async => (await Sha256().hash(data)).bytes;
List<int> _spki(List<int> prefix, List<int> key) => [...prefix, ...key];

SimplePublicKey _readSpki(String text, List<int> prefix, KeyPairType type) {
  final bytes = _unb64(text);
  if (bytes.length != prefix.length + 32 ||
      !ListEqualitySame.bytesMatch(bytes.sublist(0, prefix.length), prefix)) {
    throw const FormatException('Unexpected public key encoding');
  }
  return SimplePublicKey(bytes.sublist(prefix.length), type: type);
}

/// Constant-length byte comparison helper for the fixed ASN.1 header.
class ListEqualitySame {
  static bool bytesMatch(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) { diff |= a[i] ^ b[i]; }
    return diff == 0;
  }
}

class PairChallenge {
  final String code;
  final String fingerprint;
  final bool previouslyTrusted;
  const PairChallenge(this.code, this.fingerprint, this.previouslyTrusted);
}

class PairResult {
  final String fingerprint;
  final bool previouslyTrusted;
  final String remoteAddress;
  const PairResult(this.fingerprint, this.previouslyTrusted, this.remoteAddress);
}

typedef AskForPairConsent = Future<bool> Function(PairChallenge challenge);

/// Private seed & remembered public keys are stored with platform-backed
/// encrypted storage. Reinstall/reset may invalidate them: never silently
/// regenerate if an existing identity cannot be read correctly.
class PairingLab {
  final FlutterSecureStorage storage;
  PairingLab({FlutterSecureStorage? storage}) : storage = storage ?? const FlutterSecureStorage();
  ServerSocket? _server;
  Socket? _previewSocket;
  bool _previewCancelled = false;
  bool _busy = false;
  final Map<String, String> _trust = {};
  final Map<String, String> _sessionAddresses = {};
  SimpleKeyPair? _identity;
  List<int>? _identitySpki;
  final signature = Ed25519();
  final keyExchange = X25519();
  String? error;
  void Function()? onChange;
  bool get listening => _server != null;
  bool isPairedInThisSession(String address) => _sessionAddresses.containsKey(address);
  int get trustedCount => _trust.length;
  String? get localFingerprint => _localFingerprint;
  String? _localFingerprint;

  Future<void> _init() async {
    if (_identity != null) return;
    final saved = await storage.read(key: 'liquidremote.ed25519.seed.v1');
    if (saved != null && _unb64(saved).length != 32) {
      throw const FormatException('Stored identity invalid — refusing regeneration');
    }
    final seed = saved == null ? _rand(32) : _unb64(saved);
    final keyPair = await signature.newKeyPairFromSeed(seed);
    final pub = await keyPair.extractPublicKey();
    if (saved == null) {
      await storage.write(key: 'liquidremote.ed25519.seed.v1', value: _b64(seed));
    }
    final trustText = await storage.read(key: 'liquidremote.trust.v1');
    if (trustText != null) {
      final decoded = jsonDecode(trustText);
      if (decoded is! Map<String, dynamic>) throw const FormatException('Invalid trust database');
      for (final entry in decoded.entries) {
        if (entry.value is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.key)) {
          throw const FormatException('Invalid trust record');
        }
        final peerPublic = _readSpki(entry.value as String, _edSpki, KeyPairType.ed25519);
        final digest = _hex(await _sha(_spki(_edSpki, peerPublic.bytes)));
        if (digest != entry.key) throw const FormatException('Invalid fingerprint pin');
        _trust[entry.key] = entry.value as String;
      }
    }
    _identity = keyPair;
    _identitySpki = _spki(_edSpki, pub.bytes);
    _localFingerprint = _hex(await _sha(_identitySpki!));
    onChange?.call();
  }

  Future<void> startListening(AskForPairConsent ask) async {
    if (_server != null) return;
    try {
      await _init();
      final server = await ServerSocket.bind(InternetAddress.anyIPv4, pairingPort);
      _server = server;
      server.listen((socket) async {
        if (_busy) { socket.destroy(); return; }
        _busy = true;
        try { await _pair(socket, isClient: false, ask: ask); }
        catch (e) { error = 'Incoming pairing: $e'; onChange?.call(); }
        finally { socket.destroy(); _busy = false; }
      }, onError: (Object e) { error = 'Pair listener: $e'; onChange?.call(); });
      error = null;
    } catch (e) { error = 'Pair listener unavailable: $e'; }
    onChange?.call();
  }

  Future<PairResult> connect(String ip, AskForPairConsent ask) async {
    await _init();
    if (_busy) throw StateError('Already pairing another device');
    final parsed = InternetAddress.tryParse(ip);
    if (parsed == null || parsed.type != InternetAddressType.IPv4 || parsed.isMulticast ||
        parsed.isLoopback || parsed.address == '255.255.255.255') {
      throw const FormatException('Enter a valid LAN IPv4 address');
    }
    _busy = true;
    Socket? socket;
    try {
      socket = await Socket.connect(ip, pairingPort, timeout: const Duration(seconds: 4));
      final result = await _pair(socket, isClient: true, ask: ask);
      error = null;
      onChange?.call();
      return result;
    } finally { socket?.destroy(); _busy = false; }
  }

  /// This is a diagnostic MJPEG proof, NOT production streaming. Connect only to
  /// a manually approved Node Windows host started with --share-screen.
  Future<void> preview(String ip, AskForPairConsent ask,
      void Function(Uint8List frame) onFrame) async {
    await _init();
    if (_busy || _previewSocket != null) throw StateError('Pairing or preview already active');
    final parsed = InternetAddress.tryParse(ip);
    if (parsed == null || parsed.type != InternetAddressType.IPv4 || parsed.isMulticast ||
        parsed.isLoopback || parsed.address == '255.255.255.255') {
      throw const FormatException('Enter a valid LAN IPv4 address');
    }
    _busy = true;
    _previewCancelled = false;
    Socket? socket;
    try {
      socket = await Socket.connect(ip, pairingPort, timeout: const Duration(seconds: 4));
      _previewSocket = socket;
      await _pair(socket, isClient: true, ask: ask, previewReceiver: onFrame);
    } finally {
      socket?.destroy();
      _previewSocket = null;
      _busy = false;
      onChange?.call();
    }
  }

  void stopPreview() {
    _previewCancelled = true;
    _previewSocket?.destroy();
    _previewSocket = null;
    onChange?.call();
  }

  Future<void> revoke(String fingerprint) async {
    if (_trust.remove(fingerprint) == null) return;
    _sessionAddresses.removeWhere((_, f) => f == fingerprint);
    await storage.write(key: 'liquidremote.trust.v1', value: jsonEncode(_trust));
    onChange?.call();
  }
  Map<String, String> get trusted => Map.unmodifiable(_trust);

  Future<Map<String, dynamic>> _hello(String type, SimpleKeyPair eph, {String? clientHash}) async {
    final ephPublic = await eph.extractPublicKey();
    final data = <String, dynamic>{
      'v': _protocol, 'type': type, 'identity': _b64(_identitySpki!),
      'ephemeral': _b64(_spki(_xSpki, ephPublic.bytes)), 'nonce': _b64(_rand(24)),
      if (clientHash != null) 'clientHash': clientHash,
    };
    final signed = await signature.sign(utf8.encode(jsonEncode(data)), keyPair: _identity!);
    data['sig'] = _b64(signed.bytes);
    return data;
  }

  Future<SimplePublicKey> _verifyHello(Map<String, dynamic> frame, String expectedType) async {
    if (frame['v'] != _protocol || frame['type'] != expectedType) throw const FormatException('Invalid hello type');
    for (final field in ['identity', 'ephemeral', 'nonce', 'sig']) {
      final value = frame[field];
      if (value is! String || !RegExp(r'^[A-Za-z0-9_-]{1,255}$').hasMatch(value)) {
        throw const FormatException('Invalid hello field');
      }
    }
    if (_unb64(frame['nonce'] as String).length != 24 || _unb64(frame['sig'] as String).length != 64) {
      throw const FormatException('Invalid hello nonce/signature');
    }
    final pub = _readSpki(frame['identity'] as String, _edSpki, KeyPairType.ed25519);
    final eph = _readSpki(frame['ephemeral'] as String, _xSpki, KeyPairType.x25519);
    final unsigned = <String, dynamic>{...frame}..remove('sig');
    final verified = await signature.verify(utf8.encode(jsonEncode(unsigned)),
      signature: Signature(_unb64(frame['sig'] as String), publicKey: pub));
    if (!verified) throw const FormatException('Bad identity signature');
    return eph;
  }

  Future<PairResult> _pair(Socket socket, {required bool isClient,
      required AskForPairConsent ask, void Function(Uint8List frame)? previewReceiver}) async {
    final io = _JsonLines(socket);
    final ephemeral = await keyExchange.newKeyPair();
    try {
      late final Map<String, dynamic> clientHello;
      late final Map<String, dynamic> serverHello;
      late final SimplePublicKey remoteEph;
      if (isClient) {
        clientHello = await _hello('CLIENT_HELLO', ephemeral);
        await io.send(clientHello);
        serverHello = await io.receive();
        remoteEph = await _verifyHello(serverHello, 'SERVER_HELLO');
        final expectedHash = _b64(await _sha(utf8.encode(jsonEncode(clientHello))));
        if (serverHello['clientHash'] != expectedHash) throw const FormatException('Unbound server hello');
      } else {
        clientHello = await io.receive();
        remoteEph = await _verifyHello(clientHello, 'CLIENT_HELLO');
        serverHello = await _hello('SERVER_HELLO', ephemeral,
          clientHash: _b64(await _sha(utf8.encode(jsonEncode(clientHello)))));
        await io.send(serverHello);
      }
      final remotePublic = isClient ? serverHello['identity'] as String : clientHello['identity'] as String;
      final fingerprint = _hex(await _sha(_unb64(remotePublic)));
      final pinned = _trust[fingerprint];
      if (pinned != null && pinned != remotePublic) throw const FormatException('Identity pin mismatch');
      final transcriptHash = await _sha(utf8.encode(jsonEncode([clientHello, serverHello])));
      final sharedKey = await keyExchange.sharedSecretKey(keyPair: ephemeral,
        remotePublicKey: remoteEph);
      final sharedBytes = await sharedKey.extractBytes();
      final mac = await Hmac.sha256().calculateMac(transcriptHash, secretKey: SecretKey(sharedBytes));
      final codeInteger = ByteData.sublistView(Uint8List.fromList(mac.bytes)).getUint32(0) % 1000000;
      final code = codeInteger.toString().padLeft(6, '0');
      final allow = await ask(PairChallenge(code, fingerprint, pinned == remotePublic));
      if (!allow) throw StateError('Local user declined pairing');
      final channel = _SealedChannel(io, sharedBytes, transcriptHash, isClient: isClient);
      await channel.send({'type': 'CONFIRM'});
      final confirmation = await channel.receive();
      if (confirmation['type'] != 'CONFIRM') throw StateError('Other device did not confirm');
      // Test-only encrypted round trip. No privileges granted.
      if (isClient) {
        await channel.send({'type': 'PING', 'sentAt': DateTime.now().millisecondsSinceEpoch});
        final pong = await channel.receive();
        if (pong['type'] != 'PONG') throw StateError('Encrypted PING failed');
        if (previewReceiver != null) {
          // Pairing identity is pinned after authenticated PING, before view-only request.
          _trust[fingerprint] = remotePublic;
          await storage.write(key: 'liquidremote.trust.v1', value: jsonEncode(_trust));
          _sessionAddresses[socket.remoteAddress.address] = fingerprint;
          onChange?.call();
          await channel.send({'type':'STREAM_START', 'mode':'view-only'});
          final status = await channel.receive();
          if (status['type'] != 'STREAM_READY') {
            throw StateError('Host refused or does not support view-only preview');
          }
          await _receivePreview(channel, previewReceiver);
        }
      } else {
        final ping = await channel.receive();
        if (ping['type'] != 'PING') throw StateError('Only encrypted PING permitted');
        await channel.send({'type': 'PONG'});
      }
      // Trust is recorded ONLY after a successful authenticated round trip.
      _trust[fingerprint] = remotePublic;
      await storage.write(key: 'liquidremote.trust.v1', value: jsonEncode(_trust));
      _sessionAddresses[socket.remoteAddress.address] = fingerprint;
      onChange?.call();
      return PairResult(fingerprint, pinned == remotePublic, socket.remoteAddress.address);
    } finally { await io.close(); ephemeral.destroy(); }
  }

  Future<void> _receivePreview(_SealedChannel channel,
      void Function(Uint8List frame) onFrame) async {
    BytesBuilder? buffer;
    int? currentId;
    int expected = 0;
    int written = 0;
    int lastId = -1;
    // A disconnected host ends the session; no preview image is trusted
    // unless a complete frame passes all integrity and boundary checks.
    while (_previewSocket != null && !_previewCancelled) {
      final msg = await channel.receive().timeout(const Duration(seconds: 12));
      switch (msg['type']) {
        case 'FRAME_BEGIN':
          final id = msg['id'];
          final len = msg['bytes'];
          if (id is! int || id <= lastId || len is! int || len < 4 || len > 512 * 1024) {
            throw const FormatException('Invalid preview frame header');
          }
          currentId = id; expected = len; written = 0;
          buffer = BytesBuilder(copy: false);
          break;
        case 'FRAME_PART':
          if (buffer == null || msg['id'] != currentId || msg['offset'] != written ||
              msg['data'] is! String || (msg['data'] as String).length > 4000) {
            throw const FormatException('Invalid preview part');
          }
          final part = _unb64(msg['data'] as String);
          if (part.isEmpty || part.length > 2600 || written + part.length > expected) {
            throw const FormatException('Preview frame overflow');
          }
          buffer.add(part); written += part.length;
          break;
        case 'FRAME_END':
          if (buffer == null || msg['id'] != currentId || written != expected) {
            throw const FormatException('Incomplete preview frame');
          }
          final image = buffer.takeBytes();
          if (image[0] != 0xff || image[1] != 0xd8 ||
              image[image.length - 2] != 0xff || image.last != 0xd9) {
            throw const FormatException('Not a JPEG');
          }
          lastId = currentId!; currentId = null; buffer = null;
          onFrame(image);
          break;
        default:
          throw StateError('Unexpected preview message');
      }
    }
  }

  Future<void> stop() async { stopPreview(); await _server?.close(); _server = null; onChange?.call(); }
}

class _JsonLines {
  final Socket socket;
  late final StreamSubscription<Uint8List> _subscription;
  final List<int> _pending = [];
  final Queue<String> _lines = Queue();
  Completer<String>? _waiter;
  bool _closed = false;
  _JsonLines(this.socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    _subscription = socket.listen((data) {
      if (_closed) return;
      for (final byte in data) {
        if (byte == 10) {
          String line;
          try { line = utf8.decode(_pending); }
          catch (_) { socket.destroy(); return; }
          _pending.clear();
          if (_waiter != null) { _waiter!.complete(line); _waiter = null; }
          else { _lines.add(line); if (_lines.length > 512) { socket.destroy(); _ended(); break; } }
        } else {
          _pending.add(byte);
          if (_pending.length > _maxFrameBytes) { socket.destroy(); _ended(); break; }
        }
      }
    }, onDone: () => _ended(), onError: (Object e) => _ended());
  }
  void _ended() {
    _closed = true;
    if (_waiter != null) { _waiter!.completeError(StateError('Peer disconnected')); _waiter = null; }
  }
  Future<Map<String, dynamic>> receive() async {
    if (_closed && _lines.isEmpty) throw StateError('Peer disconnected');
    final text = _lines.isNotEmpty ? _lines.removeFirst() :
      await (() { final c = Completer<String>(); _waiter = c; return c.future; })().timeout(_timeout);
    final x = jsonDecode(text);
    if (x is! Map<String, dynamic>) throw const FormatException('Invalid network frame');
    return x;
  }
  Future<void> send(Map<String, dynamic> obj) async {
    final line = '${jsonEncode(obj)}\n';
    if (utf8.encode(line).length > _maxFrameBytes) throw StateError('Outgoing message too large');
    socket.write(line);
    await socket.flush();
  }
  Future<void> close() async { await _subscription.cancel(); socket.destroy(); _ended(); }
}

class _SealedChannel {
  final _JsonLines io;
  final List<int> shared, transcript;
  final bool isClient;
  int sent = 0, received = 0;
  _SealedChannel(this.io, this.shared, this.transcript, {required this.isClient});

  Future<SecretKey> _key(String direction) async =>
      Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(shared), nonce: transcript,
        info: utf8.encode('liquidremote/v1/$direction'));

  List<int> _nonce(String direction, int seq) {
    final bytes = ByteData(12);
    final chars = utf8.encode(direction);
    for (var i = 0; i < 4; i++) { bytes.setUint8(i, chars[i]); }
    bytes.setUint64(4, seq, Endian.big);
    return bytes.buffer.asUint8List();
  }
  Future<void> send(Map<String, dynamic> message) async {
    final direction = isClient ? 'C2S1' : 'S2C1';
    final seq = sent++;
    final box = await AesGcm.with256bits().encrypt(utf8.encode(jsonEncode(message)),
      secretKey: await _key(isClient ? 'c2s' : 's2c'), nonce: _nonce(direction, seq),
      aad: utf8.encode('$_protocol|$direction|$seq'));
    await io.send({'type': 'SEALED', 'seq': seq, 'data': _b64([...box.cipherText, ...box.mac.bytes])});
  }
  Future<Map<String, dynamic>> receive() async {
    final frame = await io.receive();
    if (frame['type'] != 'SEALED' || frame['seq'] != received || frame['data'] is! String) {
      throw StateError('Unexpected or replayed sealed frame');
    }
    final direction = isClient ? 'S2C1' : 'C2S1';
    final seq = received++;
    final data = _unb64(frame['data'] as String);
    if (data.length < 16) throw const FormatException('Invalid ciphertext');
    final output = await AesGcm.with256bits().decrypt(
      SecretBox(data.sublist(0, data.length - 16), nonce: _nonce(direction, seq),
        mac: Mac(data.sublist(data.length - 16))),
      secretKey: await _key(isClient ? 's2c' : 'c2s'),
      aad: utf8.encode('$_protocol|$direction|$seq'));
    final value = jsonDecode(utf8.decode(output));
    if (value is! Map<String, dynamic>) throw const FormatException('Invalid sealed payload');
    return value;
  }
}

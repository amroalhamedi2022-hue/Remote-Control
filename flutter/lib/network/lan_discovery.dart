// Phase 1 LAN presence/probe protocol. NOT an authenticated remote session.
// Peers and names obtained here are UNTRUSTED until pairing is implemented.
// No screen capture, input, file, or clipboard data is exchanged.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'lan_address_policy.dart';

const lanDiscoveryPort = 43827;
const lanProbePort = 43828;
const lanProtocol = 'liquid-remote.discovery.v1';

// UDP device labels are untrusted until pairing. Reject invisible direction
// controls and line separators that can impersonate another device in the UI.
// This does not authorize a peer or replace authenticated pairing.
@visibleForTesting
bool isSafeDiscoveryLabel(String value, int maxLength) {
  if (value.trim().isEmpty || value.length > maxLength) return false;
  for (final code in value.runes) {
    if (code < 0x20 || code >= 0x7f && code <= 0x9f ||
        code == 0x061c || code >= 0x200e && code <= 0x200f ||
        code >= 0x2028 && code <= 0x202e ||
        code >= 0x2066 && code <= 0x206f ||
        code == 0xfeff || code >= 0xfff9 && code <= 0xfffb) {
      return false;
    }
  }
  return true;
}

class LanPeer {
  final String id;
  final String name;
  final String platform;
  final String address;
  final int udpPort;
  final int tcpPort;
  final DateTime lastSeen;
  const LanPeer({required this.id, required this.name, required this.platform,
    required this.address, required this.udpPort, required this.tcpPort, required this.lastSeen});
}

/// Bounded cache for untrusted LAN advertisements. A noisy or malicious LAN
/// cannot grow the discovery list indefinitely by sending random device IDs.
/// This is not a trust store: entries never authorize remote operations.
@visibleForTesting
class LanPeerCache {
  final int maxPeers;
  final Map<String, LanPeer> _entries = {};

  LanPeerCache({this.maxPeers = 128}) {
    if (maxPeers < 1 || maxPeers > 4096) {
      throw ArgumentError.value(maxPeers, 'maxPeers');
    }
  }

  int get length => _entries.length;
  Iterable<LanPeer> get values => _entries.values;

  void remember(LanPeer peer) {
    if (!_entries.containsKey(peer.id) && _entries.length >= maxPeers) {
      String? oldestId;
      DateTime? oldestSeen;
      for (final entry in _entries.entries) {
        if (oldestSeen == null || entry.value.lastSeen.isBefore(oldestSeen)) {
          oldestId = entry.key;
          oldestSeen = entry.value.lastSeen;
        }
      }
      if (oldestId != null) _entries.remove(oldestId);
    }
    _entries[peer.id] = peer;
  }

  int expireBefore(DateTime deadline) {
    final before = _entries.length;
    _entries.removeWhere((_, peer) => peer.lastSeen.isBefore(deadline));
    return before - _entries.length;
  }
}

class LanDiscovery extends ChangeNotifier {
  RawDatagramSocket? _udp;
  ServerSocket? _probeServer;
  StreamSubscription<RawSocketEvent>? _udpSubscription;
  StreamSubscription<Socket>? _serverSubscription;
  Timer? _announcer;
  Timer? _sweeper;
  final LanPeerCache _peers = LanPeerCache();
  final String nodeId = List<int>.generate(16, (_) => Random.secure().nextInt(256))
      .map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  bool running = false;
  String? error;

  List<LanPeer> get peers {
    final list = _peers.values.toList()..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
    return List.unmodifiable(list);
  }

  String get deviceName {
    final name = Platform.localHostname.trim();
    if (name.isEmpty || name == 'localhost') {
      return Platform.isAndroid ? 'Android Device' : 'Windows PC';
    }
    return name.length > 64 ? name.substring(0, 64) : name;
  }

  String get devicePlatform => Platform.isAndroid ? 'Android' :
    Platform.isWindows ? 'Windows' : Platform.operatingSystem;

  Future<void> start() async {
    if (running) return;
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, lanDiscoveryPort,
          reuseAddress: true);
      _udp!.broadcastEnabled = true;
      _probeServer = await ServerSocket.bind(InternetAddress.anyIPv4, lanProbePort);
      _udpSubscription = _udp!.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = _udp?.receive()) != null) {
          _handlePacket(datagram!);
        }
      }, onError: (Object e) { error = 'UDP: $e'; notifyListeners(); });
      _serverSubscription = _probeServer!.listen(_handleProbe,
          onError: (Object e) { error = 'TCP: $e'; notifyListeners(); });
      running = true;
      error = null;
      _announce();
      _announcer = Timer.periodic(const Duration(seconds: 5), (_) => _announce());
      _sweeper = Timer.periodic(const Duration(seconds: 4), (_) {
        final deadline = DateTime.now().subtract(const Duration(seconds: 20));
        if (_peers.expireBefore(deadline) > 0) notifyListeners();
      });
      notifyListeners();
    } catch (e) {
      error = 'Local discovery unavailable: $e';
      await stop();
      notifyListeners();
    }
  }

  Map<String, Object> _message(String kind) => {
    'protocol': lanProtocol, 'kind': kind, 'id': nodeId,
    'name': deviceName, 'platform': devicePlatform,
    'tcpPort': lanProbePort,
  };

  void _send(String kind, InternetAddress address, int port) {
    if (_udp == null) return;
    final data = utf8.encode(jsonEncode(_message(kind)));
    try { _udp!.send(data, address, port); } catch (_) {
      // Missing route, interface change or denied broadcast; manual IP remains available.
    }
  }

  void _announce() {
    _send('DISCOVER', InternetAddress('255.255.255.255'), lanDiscoveryPort);
    _send('ANNOUNCE', InternetAddress('255.255.255.255'), lanDiscoveryPort);
  }

  void refresh() => _announce();

  void _handlePacket(Datagram packet) {
    // Discovery is never trusted; reject Internet/VPN public source addresses.
    if (!isLocalLanIpv4(packet.address, allowLoopback: true)) return;
    if (packet.data.length > 1200 || packet.data.isEmpty) return;
    Object payload;
    try { payload = jsonDecode(utf8.decode(packet.data)); } catch (_) { return; }
    if (payload is! Map<String, dynamic> || payload['protocol'] != lanProtocol) return;
    final kind = payload['kind'];
    if (kind != 'DISCOVER' && kind != 'ANNOUNCE') return;
    final id = payload['id'], name = payload['name'], platform = payload['platform'];
    final tcpPort = payload['tcpPort'];
    if (id is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(id) || id == nodeId ||
        name is! String || !isSafeDiscoveryLabel(name, 64) ||
        platform is! String || !isSafeDiscoveryLabel(platform, 32) ||
        tcpPort is! int || tcpPort < 1 || tcpPort > 65535) {
      return;
    }
    // Address comes from datagram source, never from an untrusted JSON field.
    final peer = LanPeer(id: id, name: name, platform: platform,
      address: packet.address.address, udpPort: packet.port,
      tcpPort: tcpPort, lastSeen: DateTime.now());
    _peers.remember(peer);
    notifyListeners();
    if (kind == 'DISCOVER') {
      _send('ANNOUNCE', packet.address, packet.port);
    }
  }

  void _handleProbe(Socket client) => respondToProbe(client);

  /// This is a source-address filter, NOT an authenticated route or a trusted peer.
  /// Keep loopback available for same-device diagnostics and unit tests.
  @visibleForTesting
  static bool isAllowedProbeSource(InternetAddress address) =>
      isLocalLanIpv4(address, allowLoopback: true);

  /// Respond to one bounded, newline-terminated TCP reachability probe.
  /// TCP packets are arbitrary chunks: a split PING must not be rejected.
  /// This is deliberately NOT pairing, authentication, or device control.
  @visibleForTesting
  static void respondToProbe(Socket client) {
    // TCP reachability is deliberately LAN-only, just like UDP discovery.
    // A private source is not proof of physical LAN membership or pairing.
    if (!isAllowedProbeSource(client.remoteAddress)) {
      client.destroy();
      return;
    }
    final request = <int>[];
    var finished = false;
    late final Timer timeout;
    void close() {
      if (finished) return;
      finished = true;
      timeout.cancel();
      client.destroy();
    }

    timeout = Timer(const Duration(seconds: 3), close);
    client.listen((chunk) {
      if (finished) return;
      for (var index = 0; index < chunk.length; index++) {
        if (request.length >= 64) {
          close();
          return;
        }
        final byte = chunk[index];
        if (byte != 10) {
          request.add(byte);
          continue;
        }
        // Reject pipelined commands and bytes after the first line.
        if (index != chunk.length - 1) {
          close();
          return;
        }
        final hasCr = request.length == 5 && request.last == 13;
        final validLength = request.length == 4 || hasCr;
        final isPing = validLength && request[0] == 80 &&
            request[1] == 73 && request[2] == 78 && request[3] == 71;
        if (!isPing) {
          close();
          return;
        }
        finished = true;
        timeout.cancel();
        client.write('PONG\n');
        client.flush().then((_) => client.destroy(),
            onError: (Object _) => client.destroy());
        return;
      }
    }, onError: (_) => close(), onDone: close);
  }

  /// Manual IP discovers a LAN agent via UDP. Use 192.168.x.x or IPv4:UDP-port.
  /// Port override is useful for local test agents, not needed for normal usage.
  Future<bool> probeManual(String input) async {
    final parts = input.trim().split(':');
    if (parts.isEmpty || parts.length > 2) return false;
    final address = InternetAddress.tryParse(parts.first);
    if (address == null || !isLocalLanIpv4(address, allowLoopback: true)) {
      return false;
    }
    final port = parts.length == 2 ? int.tryParse(parts.last) : lanDiscoveryPort;
    if (port == null || port < 1 || port > 65535) {
      return false;
    }
    _send('DISCOVER', address, port);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    return _peers.values.any((p) => p.address == address.address);
  }

  /// Returns a TCP roundtrip timing, NOT display / input latency.
  Future<Duration?> ping(LanPeer peer) async {
    // A forged LanPeer must not turn a reachability test into an Internet probe.
    if (!isLocalLanIpv4(InternetAddress.tryParse(peer.address), allowLoopback: true)) {
      return null;
    }
    Socket? socket;
    try {
      final watch = Stopwatch()..start();
      socket = await Socket.connect(peer.address, peer.tcpPort,
          timeout: const Duration(seconds: 2));
      socket.write('PING\n');
      // Never feed untrusted TCP data to an unbounded UTF-8 line decoder.
      // A malicious LAN peer can stream megabytes without a newline.
      final valid = await readProbeReply(socket.cast<List<int>>());
      watch.stop();
      return valid ? watch.elapsed : null;
    } catch (_) { return null; }
    finally { socket?.destroy(); }
  }

  /// Parse one small TCP probe response with a strict byte and time budget.
  /// This is only reachability, never authentication or control authorization.
  /// Both PONG\\n and PONG\\r\\n are accepted, including fragmented packets.
  @visibleForTesting
  static Future<bool> readProbeReply(Stream<List<int>> bytes,
      {Duration timeout = const Duration(seconds: 2)}) async {
    final done = Completer<bool>();
    final received = <int>[];
    final subscription = bytes.listen((chunk) {
      if (done.isCompleted) return;
      for (var i = 0; i < chunk.length; i++) {
        if (received.length >= 6) {
          done.complete(false);
          return;
        }
        final byte = chunk[i];
        received.add(byte);
        if (byte == 10) {
          final isPong = received.length == 5 &&
              received[0] == 80 && received[1] == 79 &&
              received[2] == 78 && received[3] == 71 ||
              received.length == 6 &&
              received[0] == 80 && received[1] == 79 &&
              received[2] == 78 && received[3] == 71 &&
              received[4] == 13;
          done.complete(isPong && i == chunk.length - 1);
          return;
        }
      }
    }, onError: (Object _) {
      if (!done.isCompleted) done.complete(false);
    }, onDone: () {
      if (!done.isCompleted) done.complete(false);
    });
    try {
      return await done.future.timeout(timeout, onTimeout: () => false);
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> stop() async {
    _announcer?.cancel(); _sweeper?.cancel();
    await _udpSubscription?.cancel();
    await _serverSubscription?.cancel();
    _udp?.close();
    await _probeServer?.close();
    _udp = null; _probeServer = null;
    running = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _announcer?.cancel(); _sweeper?.cancel();
    _udpSubscription?.cancel(); _serverSubscription?.cancel();
    _udp?.close(); _probeServer?.close();
    super.dispose();
  }
}

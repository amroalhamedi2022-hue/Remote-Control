// Phase 1 LAN presence/probe protocol. NOT an authenticated remote session.
// Peers and names obtained here are UNTRUSTED until pairing is implemented.
// No screen capture, input, file, or clipboard data is exchanged.
import 'dart:async';
import 'dart:collection';
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
        code == 0x00ad || code == 0x034f || code == 0x061c ||
        code == 0x180e || code >= 0x200b && code <= 0x200f ||
        code == 0x2060 || code == 0x3164 || code == 0xffa0 ||
        code >= 0xe0000 && code <= 0xe007f ||
        code >= 0x2028 && code <= 0x202e ||
        code >= 0x2066 && code <= 0x206f ||
        code == 0xfeff || code >= 0xfff9 && code <= 0xfffb) {
      return false;
    }
  }
  return true;
}

/// Reject malformed or self-referential discovery announcements before they can
/// steer an automatic TCP probe. The advertised endpoint is protocol-fixed;
/// manual IP probes remain a separate, explicit user action.
@visibleForTesting
bool isValidDiscoveredPeerFields({
  required String id,
  required String name,
  required String platform,
  required int tcpPort,
  required String localNodeId,
  int expectedTcpPort = lanProbePort,
}) =>
    RegExp(r'^[0-9a-f]{32}$').hasMatch(id) &&
    id != localNodeId &&
    isSafeDiscoveryLabel(name, 64) &&
    isSafeDiscoveryLabel(platform, 32) &&
    tcpPort == expectedTcpPort;

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

  bool remember(LanPeer peer) {
    // An older asynchronous sighting must not replace a fresher address or
    // keep a peer alive with obsolete metadata. These are still UNTRUSTED IDs.
    final current = _entries[peer.id];
    // Equal timestamps are not proof that a sighting is newer. Two UDP
    // packets can be observed in the same clock tick; a conflicting tie must
    // not replace the already-cached address or display metadata.
    if (current != null && !peer.lastSeen.isAfter(current.lastSeen)) return false;
    if (current == null && _entries.length >= maxPeers) {
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
    return true;
  }

  /// A manual probe succeeds only on a fresh advertisement from that address.
  /// Cached discovery alone is not evidence that a host replied to this probe.
  bool wasSeenSince(String address, DateTime startedAt) =>
      _entries.values.any((peer) =>
          peer.address == address && peer.lastSeen.isAfter(startedAt));

  int expireBefore(DateTime deadline) {
    final before = _entries.length;
    _entries.removeWhere((_, peer) => peer.lastSeen.isBefore(deadline));
    return before - _entries.length;
  }

  void clear() => _entries.clear();
}

/// Bounded response gate for unauthenticated UDP discovery. Discovery is a hint,
/// never trust or authorization; limiting replies prevents one LAN sender from
/// making this process answer every repeated broadcast without bound.
@visibleForTesting
class DiscoveryReplyGate {
  final int maxSources;
  final Duration minSourceInterval;
  final Duration minGlobalInterval;
  final Duration retention;
  final LinkedHashMap<String, Duration> _lastReplies = LinkedHashMap<String, Duration>();
  Duration? _lastAnyReply;

  DiscoveryReplyGate({
    this.maxSources = 128,
    this.minSourceInterval = const Duration(seconds: 1),
    this.minGlobalInterval = const Duration(milliseconds: 50),
    this.retention = const Duration(seconds: 30),
  }) {
    if (maxSources < 1 || maxSources > 4096) {
      throw ArgumentError.value(maxSources, 'maxSources');
    }
    if (minSourceInterval.isNegative || minGlobalInterval.isNegative ||
        retention < minSourceInterval) {
      throw ArgumentError('Invalid discovery reply-gate durations');
    }
  }

  int get trackedSources => _lastReplies.length;

  bool shouldReply(String sourceAddress, Duration elapsed) {
    if (sourceAddress.trim().isEmpty || elapsed.isNegative) return false;
    _lastReplies.removeWhere((_, previous) =>
        elapsed >= previous && elapsed - previous > retention);

    final lastForSource = _lastReplies[sourceAddress];
    if (lastForSource != null &&
        (elapsed < lastForSource || elapsed - lastForSource < minSourceInterval)) {
      return false;
    }
    final lastAny = _lastAnyReply;
    if (lastAny != null &&
        (elapsed < lastAny || elapsed - lastAny < minGlobalInterval)) {
      return false;
    }

    _lastReplies.remove(sourceAddress);
    _lastReplies[sourceAddress] = elapsed;
    _lastAnyReply = elapsed;
    while (_lastReplies.length > maxSources) {
      _lastReplies.remove(_lastReplies.keys.first);
    }
    return true;
  }

  void clear() {
    _lastReplies.clear();
    _lastAnyReply = null;
  }
}

class LanDiscovery extends ChangeNotifier {
  LanDiscovery({int discoveryPort = lanDiscoveryPort, int probePort = lanProbePort})
      : _discoveryPort = discoveryPort, _probePort = probePort;

  final int _discoveryPort;
  final int _probePort;
  int _lifecycleGeneration = 0;
  Future<void>? _startFuture;
  RawDatagramSocket? _udp;
  ServerSocket? _probeServer;
  StreamSubscription<RawSocketEvent>? _udpSubscription;
  StreamSubscription<Socket>? _serverSubscription;
  Timer? _announcer;
  Timer? _sweeper;
  final LanPeerCache _peers = LanPeerCache();
  final DiscoveryReplyGate _replyGate = DiscoveryReplyGate();
  final Stopwatch _discoveryClock = Stopwatch()..start();
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

  /// Coalesce concurrent starts and invalidate any bind still in flight when stopped.
  /// A late bind result is closed rather than resurrecting discovery after the user stops it.
  Future<void> start() {
    if (running) return Future<void>.value();
    final active = _startFuture;
    if (active != null) return active;
    final generation = ++_lifecycleGeneration;
    late final Future<void> pending;
    pending = _startGeneration(generation).whenComplete(() {
      if (identical(_startFuture, pending)) _startFuture = null;
    });
    _startFuture = pending;
    return pending;
  }

  bool _isCurrentGeneration(int generation) => generation == _lifecycleGeneration;

  Future<void> _startGeneration(int generation) async {
    RawDatagramSocket? udp;
    ServerSocket? probe;
    StreamSubscription<RawSocketEvent>? udpSubscription;
    StreamSubscription<Socket>? serverSubscription;
    try {
      udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _discoveryPort,
          reuseAddress: true);
      if (!_isCurrentGeneration(generation)) {
        udp.close();
        return;
      }
      udp.broadcastEnabled = true;
      probe = await ServerSocket.bind(InternetAddress.anyIPv4, _probePort);
      if (!_isCurrentGeneration(generation)) {
        udp.close();
        await probe.close();
        return;
      }
      udpSubscription = udp.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? datagram;
        while ((datagram = _udp?.receive()) != null) {
          _handlePacket(datagram!);
        }
      }, onError: (Object e) { error = 'UDP: $e'; notifyListeners(); });
      serverSubscription = probe.listen(_handleProbe,
          onError: (Object e) { error = 'TCP: $e'; notifyListeners(); });
      if (!_isCurrentGeneration(generation)) {
        await udpSubscription.cancel();
        await serverSubscription.cancel();
        udp.close();
        await probe.close();
        return;
      }
      _udp = udp;
      _probeServer = probe;
      _udpSubscription = udpSubscription;
      _serverSubscription = serverSubscription;
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
      await udpSubscription?.cancel();
      await serverSubscription?.cancel();
      udp?.close();
      await probe?.close();
      if (_isCurrentGeneration(generation)) {
        if (identical(_udp, udp)) _udp = null;
        if (identical(_probeServer, probe)) _probeServer = null;
        if (identical(_udpSubscription, udpSubscription)) _udpSubscription = null;
        if (identical(_serverSubscription, serverSubscription)) _serverSubscription = null;
        _announcer?.cancel();
        _sweeper?.cancel();
        running = false;
        error = 'Local discovery unavailable: $e';
        notifyListeners();
      }
    }
  }

  Map<String, Object> _message(String kind) => {
    'protocol': lanProtocol, 'kind': kind, 'id': nodeId,
    'name': deviceName, 'platform': devicePlatform,
    'tcpPort': _probeServer?.port ?? _probePort,
  };

  void _send(String kind, InternetAddress address, int port) {
    if (_udp == null) return;
    final data = utf8.encode(jsonEncode(_message(kind)));
    try { _udp!.send(data, address, port); } catch (_) {
      // Missing route, interface change or denied broadcast; manual IP remains available.
    }
  }

  void _announce() {
    final port = _udp?.port ?? _discoveryPort;
    _send('DISCOVER', InternetAddress('255.255.255.255'), port);
    _send('ANNOUNCE', InternetAddress('255.255.255.255'), port);
  }

  void refresh() => _announce();

  void _handlePacket(Datagram packet) {
    // Discovery is never trusted; reject Internet/VPN public source addresses.
    if (!isLocalLanIpv4(packet.address)) return;
    if (packet.data.length > 1200 || packet.data.isEmpty) return;
    Object payload;
    try { payload = jsonDecode(utf8.decode(packet.data)); } catch (_) { return; }
    if (payload is! Map<String, dynamic> || payload['protocol'] != lanProtocol) return;
    final kind = payload['kind'];
    if (kind != 'DISCOVER' && kind != 'ANNOUNCE') return;
    final id = payload['id'], name = payload['name'], platform = payload['platform'];
    final tcpPort = payload['tcpPort'];
    if (id is! String || name is! String || platform is! String || tcpPort is! int ||
        !isValidDiscoveredPeerFields(
          id: id, name: name, platform: platform,
          tcpPort: tcpPort, localNodeId: nodeId,
          expectedTcpPort: _probeServer?.port ?? _probePort,
        )) {
      return;
    }
    // Address comes from datagram source, never from an untrusted JSON field.
    final peer = LanPeer(id: id, name: name, platform: platform,
      address: packet.address.address, udpPort: packet.port,
      tcpPort: tcpPort, lastSeen: DateTime.now());
    final changed = _peers.remember(peer);
    if (changed) notifyListeners();
    if (kind == 'DISCOVER' &&
        _replyGate.shouldReply(packet.address.address, _discoveryClock.elapsed)) {
      _send('ANNOUNCE', packet.address, packet.port);
    }
  }

  void _handleProbe(Socket client) => respondToProbe(client);

  /// Production probe sources must be LAN IPv4. Loopback is test-only.
  @visibleForTesting
  static bool isAllowedProbeSource(InternetAddress address) =>
      isLocalLanIpv4(address);

  /// Respond to one bounded, newline-terminated TCP reachability probe.
  /// TCP packets are arbitrary chunks: a split PING must not be rejected.
  /// This is deliberately NOT pairing, authentication, or device control.
  @visibleForTesting
  static void respondToProbe(Socket client, {bool allowLoopbackForTesting = false}) {
    // The production listener uses the secure default. Loopback is an explicit
    // test-only escape hatch for isolated parser tests, never used by the UI.
    if (!isLocalLanIpv4(client.remoteAddress, allowLoopback: allowLoopbackForTesting)) {
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

  /// Manual IP discovers a LAN agent via UDP. Use private/link-local IPv4 or IPv4:UDP-port.
  /// Loopback and public addresses are never valid production discovery targets.
  Future<bool> probeManual(String input) async {
    final parts = input.trim().split(':');
    if (parts.isEmpty || parts.length > 2) return false;
    final address = InternetAddress.tryParse(parts.first);
    if (address == null || !isLocalLanIpv4(address)) {
      return false;
    }
    final port = parts.length == 2 ? int.tryParse(parts.last) : (_udp?.port ?? _discoveryPort);
    if (port == null || port < 1 || port > 65535) {
      return false;
    }
    // Do not claim a successful manual probe if discovery was never started.
    if (!running || _udp == null) return false;
    final startedAt = DateTime.now();
    _send('DISCOVER', address, port);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    return _peers.wasSeenSince(address.address, startedAt);
  }

  /// Returns a TCP roundtrip timing, NOT display / input latency.
  Future<Duration?> ping(LanPeer peer) =>
      _ping(peer, allowLoopbackForTesting: false);

  /// Loopback-only test helper. Production UI must call [ping], never this method.
  @visibleForTesting
  Future<Duration?> pingForTesting(LanPeer peer) =>
      _ping(peer, allowLoopbackForTesting: true);

  Future<Duration?> _ping(LanPeer peer, {required bool allowLoopbackForTesting}) async {
    // A forged LanPeer must not turn a reachability test into an Internet or localhost probe.
    if (!isLocalLanIpv4(InternetAddress.tryParse(peer.address),
        allowLoopback: allowLoopbackForTesting)) {
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
    var lineEnded = false;
    var validLine = false;
    final subscription = bytes.listen((chunk) {
      if (done.isCompleted) return;
      for (var i = 0; i < chunk.length; i++) {
        // Wait for EOF after a valid line so trailing bytes in a later TCP event
        // cannot be missed by returning success as soon as the newline arrives.
        if (lineEnded || received.length >= 6) {
          done.complete(false);
          return;
        }
        final byte = chunk[i];
        received.add(byte);
        if (byte == 10) {
          lineEnded = true;
          validLine = (received.length == 5 &&
                  received[0] == 80 && received[1] == 79 &&
                  received[2] == 78 && received[3] == 71) ||
              (received.length == 6 &&
                  received[0] == 80 && received[1] == 79 &&
                  received[2] == 78 && received[3] == 71 &&
                  received[4] == 13);
          if (!validLine) {
            done.complete(false);
            return;
          }
        }
      }
    }, onError: (Object _) {
      if (!done.isCompleted) done.complete(false);
    }, onDone: () {
      if (!done.isCompleted) done.complete(lineEnded && validLine);
    });
    try {
      return await done.future.timeout(timeout, onTimeout: () => false);
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> stop() async {
    // Invalidate in-flight bind operations before awaiting any cancellation.
    // Clearing the shared future allows an explicit subsequent start to proceed.
    _lifecycleGeneration++;
    _startFuture = null;
    _announcer?.cancel(); _announcer = null;
    _sweeper?.cancel(); _sweeper = null;
    final udpSubscription = _udpSubscription;
    final serverSubscription = _serverSubscription;
    final udp = _udp;
    final probe = _probeServer;
    _udpSubscription = null; _serverSubscription = null;
    _udp = null; _probeServer = null;
    running = false;
    _peers.clear();
    _replyGate.clear();
    await udpSubscription?.cancel();
    await serverSubscription?.cancel();
    udp?.close();
    await probe?.close();
    notifyListeners();
  }

  @override
  void dispose() {
    _lifecycleGeneration++;
    _startFuture = null;
    _announcer?.cancel(); _sweeper?.cancel();
    _udpSubscription?.cancel(); _serverSubscription?.cancel();
    _udp?.close(); _probeServer?.close();
    _udpSubscription = null; _serverSubscription = null;
    _udp = null; _probeServer = null;
    running = false;
    _peers.clear();
    _replyGate.clear();
    super.dispose();
  }
}

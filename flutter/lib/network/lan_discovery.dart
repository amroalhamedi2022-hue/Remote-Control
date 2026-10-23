/// Phase 1 LAN presence/probe protocol. NOT an authenticated remote session.
/// Peers and names obtained here are UNTRUSTED until pairing is implemented.
/// No screen capture, input, file, or clipboard data is exchanged.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

const lanDiscoveryPort = 43827;
const lanProbePort = 43828;
const lanProtocol = 'liquid-remote.discovery.v1';

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

class LanDiscovery extends ChangeNotifier {
  RawDatagramSocket? _udp;
  ServerSocket? _probeServer;
  StreamSubscription<RawSocketEvent>? _udpSubscription;
  StreamSubscription<Socket>? _serverSubscription;
  Timer? _announcer;
  Timer? _sweeper;
  final Map<String, LanPeer> _peers = {};
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
        final before = _peers.length;
        _peers.removeWhere((_, peer) => peer.lastSeen.isBefore(deadline));
        if (_peers.length != before) notifyListeners();
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
    if (packet.data.length > 1200 || packet.data.isEmpty) return;
    Object payload;
    try { payload = jsonDecode(utf8.decode(packet.data)); } catch (_) { return; }
    if (payload is! Map<String, dynamic> || payload['protocol'] != lanProtocol) return;
    final kind = payload['kind'];
    if (kind != 'DISCOVER' && kind != 'ANNOUNCE') return;
    final id = payload['id'], name = payload['name'], platform = payload['platform'];
    final tcpPort = payload['tcpPort'];
    if (id is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(id) || id == nodeId ||
        name is! String || name.isEmpty || name.length > 64 ||
        platform is! String || platform.length > 32 ||
        tcpPort is! int || tcpPort < 1 || tcpPort > 65535) return;
    // Address comes from datagram source, never from an untrusted JSON field.
    final peer = LanPeer(id: id, name: name, platform: platform,
      address: packet.address.address, udpPort: packet.port,
      tcpPort: tcpPort, lastSeen: DateTime.now());
    _peers[id] = peer;
    notifyListeners();
    if (kind == 'DISCOVER') _send('ANNOUNCE', packet.address, packet.port);
  }

  void _handleProbe(Socket client) {
    // Connectivity test only. No device access is granted by this listener.
    final timeout = Timer(const Duration(seconds: 3), () => client.destroy());
    var used = false;
    client.listen((bytes) {
      if (used || bytes.length > 64) { client.destroy(); return; }
      used = true;
      if (utf8.decode(bytes, allowMalformed: true).trim() == 'PING') {
        client.write('PONG\n');
        client.flush().then((_) => client.destroy());
      } else {
        client.destroy();
      }
    }, onError: (_) => client.destroy(), onDone: () => timeout.cancel());
  }

  /// Manual IP discovers a LAN agent via UDP. Use 192.168.x.x or IPv4:UDP-port.
  /// Port override is useful for local test agents, not needed for normal usage.
  Future<bool> probeManual(String input) async {
    final parts = input.trim().split(':');
    if (parts.isEmpty || parts.length > 2) return false;
    final address = InternetAddress.tryParse(parts.first);
    if (address == null || address.type != InternetAddressType.IPv4 ||
        address.isMulticast || address.address == '255.255.255.255') return false;
    final port = parts.length == 2 ? int.tryParse(parts.last) : lanDiscoveryPort;
    if (port == null || port < 1 || port > 65535) return false;
    _send('DISCOVER', address, port);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    return _peers.values.any((p) => p.address == address.address);
  }

  /// Returns a TCP roundtrip timing, NOT display / input latency.
  Future<Duration?> ping(LanPeer peer) async {
    Socket? socket;
    try {
      final watch = Stopwatch()..start();
      socket = await Socket.connect(peer.address, peer.tcpPort,
          timeout: const Duration(seconds: 2));
      socket.write('PING\n');
      final response = await socket.transform(utf8.decoder).first
        .timeout(const Duration(seconds: 2));
      watch.stop();
      return response.trim() == 'PONG' ? watch.elapsed : null;
    } catch (_) { return null; }
    finally { socket?.destroy(); }
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

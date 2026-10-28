import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/network/lan_discovery.dart';

void main() {
  group('LAN discovery announcement policy', () {
    const localId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const peerId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

    bool accepts({
      String id = peerId,
      String name = 'MSI Sword 15',
      String platform = 'Windows',
      int tcpPort = lanProbePort,
      String localNodeId = localId,
    }) => isValidDiscoveredPeerFields(
      id: id, name: name, platform: platform,
      tcpPort: tcpPort, localNodeId: localNodeId,
    );

    test('accepts a well-formed peer on the fixed probe port', () {
      expect(accepts(), isTrue);
      expect(accepts(name: 'جهاز أندرويد', platform: 'Android'), isTrue);
    });

    test('rejects advertised ports that could steer probes at unrelated LAN services', () {
      for (final port in [1, 22, 80, 443, 445, 65535]) {
        expect(accepts(tcpPort: port), isFalse, reason: 'port $port is not the probe port');
      }
    });

    test('rejects self identity, malformed IDs and unsafe display labels', () {
      expect(accepts(id: localId), isFalse);
      expect(accepts(id: 'not-a-node-id'), isFalse);
      expect(accepts(name: 'host\u202Etxt'), isFalse);
      expect(accepts(platform: ''), isFalse);
    });
  });

  Future<Duration?> runProbe(List<String> replies) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((client) {
      var replied = false;
      client.listen((bytes) async {
        if (replied) return;
        replied = true;
        if (!utf8.decode(bytes, allowMalformed: true).contains('PING')) {
          client.destroy();
          return;
        }
        for (final part in replies) {
          client.add(utf8.encode(part));
          await client.flush();
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        await client.close();
      });
    });
    final discovery = LanDiscovery();
    try {
      final peer = LanPeer(
        id: '0123456789abcdef0123456789abcdef',
        name: 'Test host',
        platform: 'Windows',
        address: InternetAddress.loopbackIPv4.address,
        udpPort: lanDiscoveryPort,
        tcpPort: server.port,
        lastSeen: DateTime.now(),
      );
      return await discovery.pingForTesting(peer);
    } finally {
      discovery.dispose();
      await subscription.cancel();
      await server.close();
    }
  }

  Future<String> runInboundProbe(List<String> chunks, {bool allowLoopbackForTesting = false}) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((client) =>
        LanDiscovery.respondToProbe(client, allowLoopbackForTesting: allowLoopbackForTesting));
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, server.port);
    try {
      final response = socket.cast<List<int>>().transform(utf8.decoder)
          .join().timeout(const Duration(seconds: 4));
      for (final chunk in chunks) {
        socket.add(utf8.encode(chunk));
        await socket.flush();
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      try {
        return await response;
      } catch (_) {
        return '';
      }
    } finally {
      socket.destroy();
      await subscription.cancel();
      await server.close();
    }
  }

  test('Production inbound TCP PING rejects loopback clients', () async {
    expect(await runInboundProbe(['PING\n']), isEmpty);
  });

  test('Inbound TCP PING accepts fragments split across packets', () async {
    expect(await runInboundProbe(['PI', 'NG\n'], allowLoopbackForTesting: true), 'PONG\n');
  });

  test('Inbound TCP PING accepts CRLF line endings', () async {
    expect(await runInboundProbe(['PING\r\n'], allowLoopbackForTesting: true), 'PONG\n');
  });

  test('Inbound TCP probe rejects malformed and oversized commands', () async {
    expect(await runInboundProbe(['PONG\n'], allowLoopbackForTesting: true), isEmpty);
    expect(await runInboundProbe(['X' * 70], allowLoopbackForTesting: true), isEmpty);
    expect(await runInboundProbe(['PING\nPONG\n'], allowLoopbackForTesting: true), isEmpty);
  });

  test('TCP reachability accepts a PONG fragmented across packets', () async {
    expect(await runProbe(['PO', 'NG\n']), isNotNull);
  });

  test('TCP probe accepts CRLF and packet boundaries', () async {
    final bytes = Stream<List<int>>.fromIterable([
      utf8.encode('PO'), utf8.encode('NG\r'), utf8.encode('\n'),
    ]);
    expect(await LanDiscovery.readProbeReply(bytes), isTrue);
  });

  test('TCP probe rejects excess bytes after a valid line', () async {
    expect(await LanDiscovery.readProbeReply(
      Stream<List<int>>.value(utf8.encode('PONG\nEXTRA'))), isFalse);
  });

  test('TCP probe rejects trailing bytes delivered in a later event', () async {
    final reply = Stream<List<int>>.fromIterable([
      utf8.encode('PONG\n'),
      utf8.encode('EXTRA'),
    ]);
    expect(await LanDiscovery.readProbeReply(reply), isFalse);
  });

  test('TCP probe requires EOF after a complete PONG line', () async {
    final controller = StreamController<List<int>>();
    final pending = LanDiscovery.readProbeReply(
      controller.stream, timeout: const Duration(milliseconds: 40));
    controller.add(utf8.encode('PONG\n'));
    expect(await pending, isFalse);
    await controller.close();
  });

  test('TCP probe rejects unbounded no-newline payloads promptly', () async {
    final stream = Stream<List<int>>.value(List<int>.filled(65536, 65));
    final watch = Stopwatch()..start();
    expect(await LanDiscovery.readProbeReply(stream), isFalse);
    expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test('TCP probe times out if a peer never finishes its line', () async {
    final stream = Stream<List<int>>.periodic(
      const Duration(milliseconds: 5), (_) => <int>[80]);
    expect(await LanDiscovery.readProbeReply(stream,
      timeout: const Duration(milliseconds: 45)), isFalse);
  });

  test('TCP reachability rejects a non-PONG reply', () async {
    expect(await runProbe(['NOT_PONG\n']), isNull);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/network/lan_discovery.dart';

void main() {
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
      return await discovery.ping(peer);
    } finally {
      discovery.dispose();
      await subscription.cancel();
      await server.close();
    }
  }

  Future<String> runInboundProbe(List<String> chunks) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen(LanDiscovery.respondToProbe);
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

  test('Inbound TCP PING accepts fragments split across packets', () async {
    expect(await runInboundProbe(['PI', 'NG\n']), 'PONG\n');
  });

  test('Inbound TCP PING accepts CRLF line endings', () async {
    expect(await runInboundProbe(['PING\r\n']), 'PONG\n');
  });

  test('Inbound TCP probe rejects malformed and oversized commands', () async {
    expect(await runInboundProbe(['PONG\n']), isEmpty);
    expect(await runInboundProbe(['X' * 70]), isEmpty);
    expect(await runInboundProbe(['PING\nPONG\n']), isEmpty);
  });

  test('TCP reachability accepts a PONG fragmented across packets', () async {
    expect(await runProbe(['PO', 'NG\n']), isNotNull);
  });

  test('TCP reachability rejects a non-PONG reply', () async {
    expect(await runProbe(['NOT_PONG\n']), isNull);
  });
}

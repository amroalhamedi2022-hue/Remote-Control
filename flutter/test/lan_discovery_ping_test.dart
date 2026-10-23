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

  test('TCP reachability accepts a PONG fragmented across packets', () async {
    expect(await runProbe(['PO', 'NG\n']), isNotNull);
  });

  test('TCP reachability rejects a non-PONG reply', () async {
    expect(await runProbe(['NOT_PONG\n']), isNull);
  });
}

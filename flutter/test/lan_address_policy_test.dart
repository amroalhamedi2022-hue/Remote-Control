import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/network/lan_address_policy.dart';
import 'package:liquid_remote_control/network/lan_discovery.dart';

void main() {
  test('Private RFC1918 and link-local IPv4 addresses are permitted', () {
    for (final ip in [
      '10.0.0.1', '10.255.255.254',
      '172.16.0.1', '172.31.255.254',
      '192.168.0.1', '192.168.255.254',
      '169.254.1.1',
    ]) {
      expect(isLocalLanIpv4(InternetAddress(ip)), isTrue, reason: ip);
    }
  });

  test('Public, multicast, special and neighboring non-LAN ranges are rejected', () {
    for (final ip in [
      '0.0.0.0', '8.8.8.8', '1.1.1.1', '203.0.113.10',
      '172.15.255.255', '172.32.0.1',
      '169.253.255.255', '169.255.0.1',
      '192.167.1.1', '192.169.1.1',
      '100.64.0.1', '224.0.0.1', '255.255.255.255',
      '127.0.0.1',
    ]) {
      expect(isLocalLanIpv4(InternetAddress(ip)), isFalse, reason: ip);
    }
    expect(isLocalLanIpv4(InternetAddress('fe80::1')), isFalse);
    expect(isLocalLanIpv4(null), isFalse);
  });

  test('Loopback is permitted only when explicitly opted in for local tests', () {
    final loopback = InternetAddress.loopbackIPv4;
    expect(isLocalLanIpv4(loopback), isFalse);
    expect(isLocalLanIpv4(loopback, allowLoopback: true), isTrue);
  });

  test('Manual discovery rejects public addresses without sending packets', () async {
    final discovery = LanDiscovery();
    try {
      expect(await discovery.probeManual('8.8.8.8'), isFalse);
      expect(await discovery.probeManual('172.32.0.1:43827'), isFalse);
      expect(await discovery.probeManual('203.0.113.1'), isFalse);
      expect(await discovery.probeManual('0.0.0.0'), isFalse);
      expect(await discovery.probeManual('fe80::1'), isFalse);
    } finally {
      discovery.dispose();
    }
  });

  test('TCP ping refuses a public address without opening a socket', () async {
    final discovery = LanDiscovery();
    try {
      final peer = LanPeer(
        id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        name: 'Untrusted public address',
        platform: 'Windows',
        address: '203.0.113.2',
        udpPort: lanDiscoveryPort,
        tcpPort: lanProbePort,
        lastSeen: DateTime.now(),
      );
      expect(await discovery.ping(peer), isNull);
    } finally {
      discovery.dispose();
    }
  });
}

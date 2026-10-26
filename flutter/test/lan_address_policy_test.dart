import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/network/lan_address_policy.dart';
import 'package:liquid_remote_control/network/lan_discovery.dart';

void main() {
  test('UDP labels reject bidi spoofing, controls and invisible separators', () {
    for (final code in [0x061c, 0x200e, 0x200f, 0x202a, 0x202e,
      0x2066, 0x206f, 0x0085, 0x2028, 0xfeff, 0xfff9, 0x000a,
      0x00ad, 0x034f, 0x180e, 0x200b, 0x200c, 0x200d,
      0x2060, 0x3164, 0xffa0, 0xe0001, 0xe007f]) {
      final deceptive = 'Host${String.fromCharCode(code)}Fake';
      expect(isSafeDiscoveryLabel(deceptive, 64), isFalse, reason: code.toString());
    }
    expect(isSafeDiscoveryLabel(' ', 64), isFalse);
    expect(isSafeDiscoveryLabel('', 64), isFalse);
    expect(isSafeDiscoveryLabel('X' * 65, 64), isFalse);
    expect(isSafeDiscoveryLabel('جهاز أندرويد', 64), isTrue);
    expect(isSafeDiscoveryLabel('Windows Host', 32), isTrue);
  });

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

  test('Inbound Flutter TCP responder rejects non-LAN sources', () {
    for (final ip in ['8.8.8.8', '203.0.113.10', '100.64.1.2',
      '224.0.0.1', '0.0.0.0', 'fe80::1', '127.0.0.1']) {
      expect(LanDiscovery.isAllowedProbeSource(InternetAddress(ip)),
        isFalse, reason: ip);
    }
    for (final ip in ['192.168.1.5', '172.16.0.1',
      '10.0.0.8', '169.254.1.2']) {
      expect(LanDiscovery.isAllowedProbeSource(InternetAddress(ip)),
        isTrue, reason: ip);
    }
  });

  test('Loopback remains test-only and cannot reach the production pairing listener', () {
    final loopback = InternetAddress.loopbackIPv4;
    expect(isLocalLanIpv4(loopback), isFalse);
    expect(isLocalLanIpv4(loopback, allowLoopback: true), isTrue);
    expect(isAllowedPairingSource(loopback), isFalse);
    expect(LanDiscovery.isAllowedProbeSource(loopback), isFalse);
    expect(isAllowedPairingSource(InternetAddress('192.168.1.9')), isTrue);
    expect(isAllowedPairingSource(InternetAddress('8.8.8.8')), isFalse);
    expect(isAllowedPairingSource(null), isFalse);
  });

  test('Manual discovery rejects public addresses without sending packets', () async {
    final discovery = LanDiscovery();
    try {
      expect(await discovery.probeManual('8.8.8.8'), isFalse);
      expect(await discovery.probeManual('127.0.0.1'), isFalse);
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

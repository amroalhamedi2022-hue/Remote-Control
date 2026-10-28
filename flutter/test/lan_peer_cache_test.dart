import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/network/lan_discovery.dart';

void main() {
  final now = DateTime.utc(2026, 10, 23, 12);
  LanPeer peer(String id, DateTime seen) => LanPeer(
    id: id,
    name: 'جهاز $id',
    platform: 'Android',
    address: '192.168.1.2',
    udpPort: lanDiscoveryPort,
    tcpPort: lanProbePort,
    lastSeen: seen,
  );

  test('Untrusted discovery cache evicts the oldest when full', () {
    final cache = LanPeerCache(maxPeers: 3);
    cache.remember(peer('a', now.subtract(const Duration(seconds: 30))));
    cache.remember(peer('b', now.subtract(const Duration(seconds: 20))));
    cache.remember(peer('c', now.subtract(const Duration(seconds: 10))));
    cache.remember(peer('d', now));
    expect(cache.length, 3);
    expect(cache.values.map((p) => p.id).toSet(), {'b', 'c', 'd'});
  });

  test('Refresh updates a known peer without evicting a different device', () {
    final cache = LanPeerCache(maxPeers: 2);
    cache.remember(peer('a', now.subtract(const Duration(seconds: 40))));
    cache.remember(peer('b', now.subtract(const Duration(seconds: 30))));
    cache.remember(peer('a', now));
    cache.remember(peer('c', now.add(const Duration(seconds: 1))));
    expect(cache.values.map((p) => p.id).toSet(), {'a', 'c'});
  });

  test('Late stale sightings cannot overwrite a fresher peer address', () {
    final cache = LanPeerCache(maxPeers: 2);
    cache.remember(peer('same', now));
    final late = LanPeer(id: 'same', name: 'Stale spoof', platform: 'Windows',
      address: '192.168.1.99', udpPort: lanDiscoveryPort,
      tcpPort: lanProbePort, lastSeen: now.subtract(const Duration(seconds: 3)));
    cache.remember(late);
    expect(cache.length, 1);
    expect(cache.values.single.address, '192.168.1.2');
    expect(cache.values.single.name, 'جهاز same');
    cache.remember(peer('new', now));
    expect(cache.values.map((p) => p.id).toSet(), {'same', 'new'});
  });

  test('Equal-timestamp conflicting sightings cannot replace cached peer metadata', () {
    final cache = LanPeerCache(maxPeers: 2);
    cache.remember(peer('same', now));
    final tied = LanPeer(
      id: 'same',
      name: 'Spoofed replacement',
      platform: 'Windows',
      address: '192.168.1.99',
      udpPort: lanDiscoveryPort,
      tcpPort: lanProbePort,
      lastSeen: now,
    );
    cache.remember(tied);
    expect(cache.length, 1);
    expect(cache.values.single.address, '192.168.1.2');
    expect(cache.values.single.name, 'جهاز same');
    expect(cache.values.single.platform, 'Android');
  });

  test('Expiry removes stale entries and keeps recent peers', () {
    final cache = LanPeerCache(maxPeers: 3);
    cache.remember(peer('old', now.subtract(const Duration(seconds: 21))));
    cache.remember(peer('edge', now.subtract(const Duration(seconds: 20))));
    cache.remember(peer('new', now));
    expect(cache.expireBefore(now.subtract(const Duration(seconds: 20))), 1);
    expect(cache.values.map((p) => p.id).toSet(), {'edge', 'new'});
    expect(cache.expireBefore(now.subtract(const Duration(seconds: 20))), 0);
    cache.clear();
    expect(cache.length, 0);
    expect(cache.values, isEmpty);
  });

  test('Manual IP requires a fresh sighting from the requested address', () {
    final cache = LanPeerCache();
    final requestedAt = now;
    cache.remember(peer('old', now.subtract(const Duration(seconds: 1))));
    expect(cache.wasSeenSince('192.168.1.2', requestedAt), isFalse,
      reason: 'A cached peer must not make a new probe appear successful');
    cache.remember(peer('new', now.add(const Duration(milliseconds: 1))));
    expect(cache.wasSeenSince('192.168.1.2', requestedAt), isTrue);
    expect(cache.wasSeenSince('192.168.1.3', requestedAt), isFalse);
    expect(cache.wasSeenSince('192.168.1.2', now.add(const Duration(seconds: 2))), isFalse);
    cache.clear();
    expect(cache.wasSeenSince('192.168.1.2', requestedAt), isFalse);
  });

  test('Cache capacity must be positive and bounded', () {
    expect(() => LanPeerCache(maxPeers: 0), throwsArgumentError);
    expect(() => LanPeerCache(maxPeers: 4097), throwsArgumentError);
  });
}

// Ephemeral pairing indicator only. This is NOT authorization for screen,
// input, files or clipboard; those require a reviewed authenticated channel
// and explicit per-operation host consent.
class PairSessionLedger {
  PairSessionLedger({
    this.lifetime = const Duration(minutes: 10),
    this.maxEntries = 64,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (lifetime <= Duration.zero || maxEntries < 1) {
      throw ArgumentError('Pairing session limits must be positive');
    }
  }

  final Duration lifetime;
  final int maxEntries;
  final DateTime Function() _clock;
  final Map<String, _PairLease> _entries = {};

  void remember(String address, String fingerprint) {
    if (address.isEmpty || fingerprint.isEmpty) {
      throw ArgumentError('Pairing identity and address must not be empty');
    }
    final now = _clock();
    _purge(now);
    // Re-pairing refreshes this address; oldest entries are evicted first.
    _entries.remove(address);
    while (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[address] = _PairLease(fingerprint, now.add(lifetime));
  }

  bool contains(String address) {
    _purge(_clock());
    return _entries.containsKey(address);
  }

  void revokeFingerprint(String fingerprint) {
    _entries.removeWhere((_, lease) => lease.fingerprint == fingerprint);
  }

  void clear() => _entries.clear();

  void _purge(DateTime now) {
    _entries.removeWhere((_, lease) => !now.isBefore(lease.expiresAt));
  }
}

class _PairLease {
  const _PairLease(this.fingerprint, this.expiresAt);
  final String fingerprint;
  final DateTime expiresAt;
}

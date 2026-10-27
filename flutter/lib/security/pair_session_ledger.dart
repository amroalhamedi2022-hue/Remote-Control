// Ephemeral pairing indicator only. This is NOT authorization for screen,
// input, files or clipboard; those require a reviewed authenticated channel
// and explicit per-operation host consent.
class PairSessionLedger {
  PairSessionLedger({
    this.lifetime = const Duration(minutes: 10),
    this.maxEntries = 64,
    int Function()? monotonicMicros,
  }) : _monotonicMicros = monotonicMicros {
    if (lifetime <= Duration.zero || maxEntries < 1) {
      throw ArgumentError('Pairing session limits must be positive');
    }
  }

  final Duration lifetime;
  final int maxEntries;
  final int Function()? _monotonicMicros;
  final Stopwatch _watch = Stopwatch()..start();
  final Map<String, _PairLease> _entries = {};
  int? _lastObservedMicros;

  int _readNowMicros() {
    final now = _monotonicMicros?.call() ?? _watch.elapsedMicroseconds;
    final previous = _lastObservedMicros;
    if (previous != null && now < previous) {
      // A broken/injected clock must fail closed rather than extend old trust
      // indicators after a clock rollback.
      _entries.clear();
      _lastObservedMicros = now;
      throw StateError('Pairing monotonic clock moved backwards');
    }
    _lastObservedMicros = now;
    return now;
  }

  void remember(String address, String fingerprint) {
    if (address.isEmpty || fingerprint.isEmpty) {
      throw ArgumentError('Pairing identity and address must not be empty');
    }
    final now = _readNowMicros();
    _purge(now);
    // Re-pairing refreshes this address; oldest entries are evicted first.
    _entries.remove(address);
    while (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[address] = _PairLease(fingerprint, now);
  }

  bool contains(String address) {
    _purge(_readNowMicros());
    return _entries.containsKey(address);
  }

  /// A recent IP alone is never proof that the same cryptographic peer returned.
  /// The caller must check this fingerprint against its currently trusted pins.
  String? fingerprintFor(String address) {
    _purge(_readNowMicros());
    return _entries[address]?.fingerprint;
  }

  void revokeFingerprint(String fingerprint) {
    _entries.removeWhere((_, lease) => lease.fingerprint == fingerprint);
  }

  void clear() => _entries.clear();

  void _purge(int nowMicros) {
    _entries.removeWhere((_, lease) =>
      nowMicros - lease.createdAtMicros >= lifetime.inMicroseconds);
  }
}

class _PairLease {
  const _PairLease(this.fingerprint, this.createdAtMicros);
  final String fingerprint;
  final int createdAtMicros;
}

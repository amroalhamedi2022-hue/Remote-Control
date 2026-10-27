// Ephemeral pairing indicator only. This is NOT authorization for screen,
// input, files or clipboard; those require a reviewed authenticated channel
// and explicit per-operation host consent.
class PairSessionLedger {
  static const int maxAddressLength = 128;
  static const int maxFingerprintLength = 256;
  // Keep a malformed caller from turning this UI-only ledger into an unbounded
  // memory sink. These limits do not imply that a lease grants trust.
  static const int maxAllowedEntries = 4096;
  static const Duration maxAllowedLifetime = Duration(days: 1);

  static bool _isSafeIdentifier(String value, int maxLength) {
    if (value.isEmpty || value.length > maxLength) return false;
    for (final rune in value.runes) {
      if (rune < 0x20 ||
          (rune >= 0x7f && rune <= 0x9f) ||
          rune == 0xfffd || rune == 0x00ad || rune == 0x034f ||
          rune == 0x061c || rune == 0x180e || rune == 0x200b ||
          (rune >= 0x200e && rune <= 0x200f) ||
          (rune >= 0x2028 && rune <= 0x202e) ||
          (rune >= 0x2060 && rune <= 0x206f) ||
          rune == 0xfeff || (rune >= 0xfff9 && rune <= 0xfffb) ||
          (rune >= 0xe0000 && rune <= 0xe007f)) {
        return false;
      }
    }
    return true;
  }

  PairSessionLedger({
    this.lifetime = const Duration(minutes: 10),
    this.maxEntries = 64,
    int Function()? monotonicMicros,
  }) : _monotonicMicros = monotonicMicros {
    if (lifetime <= Duration.zero ||
        lifetime > maxAllowedLifetime ||
        maxEntries < 1 ||
        maxEntries > maxAllowedEntries) {
      throw ArgumentError('Pairing session limits are outside safe bounds');
    }
  }

  final Duration lifetime;
  final int maxEntries;
  final int Function()? _monotonicMicros;
  final Stopwatch _watch = Stopwatch()..start();
  final Map<String, _PairLease> _entries = {};
  int? _lastObservedMicros;
  bool _clockBroken = false;

  /// Number of currently valid indicators, after expiring old leases.
  ///
  /// This remains a local diagnostic only; it does not grant trust or authorize
  /// remote operations. Reading it also applies the same monotonic-clock
  /// rollback policy as contains() and fingerprintFor().
  int get length {
    _purge(_readNowMicros());
    return _entries.length;
  }

  int _readNowMicros() {
    if (_clockBroken) {
      throw StateError('Pairing monotonic clock is invalid; create a new session ledger');
    }
    late final int now;
    try {
      now = _monotonicMicros?.call() ?? _watch.elapsedMicroseconds;
    } catch (error, stackTrace) {
      _entries.clear();
      _clockBroken = true;
      Error.throwWithStackTrace(
        StateError('Pairing monotonic clock failed; create a new session ledger: $error'),
        stackTrace,
      );
    }
    final previous = _lastObservedMicros;
    if (now < 0 || (previous != null && now < previous)) {
      // A negative or rolled-back clock invalidates this ledger for its lifetime.
      // Clearing then accepting new entries after recovery could revive stale UI state.
      _entries.clear();
      _clockBroken = true;
      throw StateError('Pairing monotonic clock is invalid or moved backwards');
    }
    _lastObservedMicros = now;
    return now;
  }

  void remember(String address, String fingerprint) {
    if (!_isSafeIdentifier(address, maxAddressLength) ||
        !_isSafeIdentifier(fingerprint, maxFingerprintLength)) {
      throw ArgumentError('Pairing identity/address is malformed or exceeds its safe bound');
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
    // Revocation is a ledger operation too: observe the monotonic clock first.
    // If it regressed, _readNowMicros clears every lease and permanently fails closed.
    final now = _readNowMicros();
    _purge(now);
    _entries.removeWhere((_, lease) => lease.fingerprint == fingerprint);
  }

  /// Clearing indicators does not repair a broken clock; callers must create a
  /// fresh ledger as part of a new pairing-session lifecycle.
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

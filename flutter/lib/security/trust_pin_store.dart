/// Serializes durable peer-pin changes and rolls back a pin if pairing is
/// stopped or the trust set changes while platform storage is awaiting.
/// This is trust persistence only; a pin never grants screen/input/file access.
typedef TrustSnapshotWriter = Future<void> Function(Map<String, String> snapshot);

class TrustPinStore {
  TrustPinStore({required TrustSnapshotWriter writeSnapshot})
      : _writeSnapshot = writeSnapshot;

  final TrustSnapshotWriter _writeSnapshot;
  final Map<String, String> _pins = <String, String>{};
  Future<void> _writeTail = Future<void>.value();
  int _revision = 0;

  Map<String, String> get values => Map<String, String>.unmodifiable(_pins);
  int get length => _pins.length;
  bool containsKey(String fingerprint) => _pins.containsKey(fingerprint);
  String? operator [](String fingerprint) => _pins[fingerprint];

  /// Loads already-validated pins during startup; does not write them back.
  void load(Map<String, String> snapshot) {
    _pins
      ..clear()
      ..addAll(snapshot);
    _revision++;
  }

  Future<void> pinIfCurrent(
    String fingerprint,
    String publicKey, {
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) throw StateError('Pairing session was stopped');
    if (_pins[fingerprint] == publicKey) return;

    final revision = _revision;
    final candidate = Map<String, String>.of(_pins)
      ..[fingerprint] = publicKey;
    try {
      await _enqueue(candidate);
    } catch (_) {
      // A platform write can fail after an uncertain partial update. Reassert
      // the current in-memory snapshot before returning the original failure.
      try { await _enqueue(Map<String, String>.of(_pins)); } catch (_) {}
      rethrow;
    }

    // Stop/revoke may run while secure storage is awaiting. Do not publish the
    // candidate to memory, and serialize a compensating snapshot after any
    // concurrent write so the stale candidate cannot be the last durable value.
    if (!isCurrent() || _revision != revision) {
      await _enqueue(Map<String, String>.of(_pins));
      if (!isCurrent()) throw StateError('Pairing session was stopped');
      throw StateError('Trust set changed during pairing');
    }

    _pins
      ..clear()
      ..addAll(candidate);
    _revision++;
  }

  /// Waits for all earlier writes and persists the current in-memory set.
  /// Pairing Stop uses this as a barrier after invalidating its generation.
  Future<void> persistCurrent() => _enqueue(Map<String, String>.of(_pins));

  /// Removes the pin from memory before awaiting storage, so a concurrent
  /// in-flight pin commit sees the revision change and cannot overwrite revoke.
  Future<bool> revoke(String fingerprint) async {
    if (!_pins.containsKey(fingerprint)) return false;
    _pins.remove(fingerprint);
    _revision++;
    final current = Map<String, String>.of(_pins);
    try {
      await _enqueue(current);
    } catch (_, stackTrace) {
      // Secure storage can report a transient failure after an uncertain write.
      // Retry the revoked snapshot before returning success, so an older durable
      // pin is not left behind merely because the first write failed.
      try {
        await _enqueue(Map<String, String>.of(_pins));
      } catch (_) {
        Error.throwWithStackTrace(
          StateError('Trust revocation could not be persisted after retry; durable trust may survive restart'),
          stackTrace,
        );
      }
    }
    return true;
  }

  Future<void> _enqueue(Map<String, String> snapshot) {
    final stable = Map<String, String>.unmodifiable(snapshot);
    final operation = _writeTail.then((_) => _writeSnapshot(stable));
    // Keep the queue usable after a failed write; the individual caller still
    // receives that failure from [operation].
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }
}

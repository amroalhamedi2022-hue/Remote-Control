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

  /// Loads already-validated pins once, before any mutation or queued write.
  void load(Map<String, String> snapshot) {
    if (_revision != 0) {
      throw StateError('Trust snapshot may only be loaded before mutations');
    }
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

    // Reserve the revision before queuing I/O. A newer revoke/stop must make
    // an older queued snapshot ineligible to become the last durable write.
    final revision = ++_revision;
    final candidate = Map<String, String>.of(_pins)
      ..[fingerprint] = publicKey;
    try {
      final persisted = await _enqueue(candidate, revision: revision);
      if (!persisted) throw StateError('Trust set changed during pairing');
    } catch (_) {
      // A platform write can fail after an uncertain partial update. Reassert
      // the old in-memory snapshot only if no newer mutation owns persistence.
      if (_revision == revision) {
        try { await _enqueue(Map<String, String>.of(_pins), revision: revision); } catch (_) {}
      }
      rethrow;
    }

    if (!isCurrent() || _revision != revision) {
      // A stale candidate may have reached storage while an async write was
      // in flight. Reassert current state only while this revision still owns
      // the queue; newer mutations enqueue their own snapshot.
      if (_revision == revision) {
        try { await _enqueue(Map<String, String>.of(_pins), revision: revision); } catch (_) {}
      }
      if (!isCurrent()) throw StateError('Pairing session was stopped');
      throw StateError('Trust set changed during pairing');
    }

    _pins
      ..clear()
      ..addAll(candidate);
    _revision++;
  }

  /// Pairing Stop uses this as a barrier after invalidating its generation.
  /// Retry if another mutation supersedes this snapshot while storage is awaiting.
  Future<void> persistCurrent() async {
    while (true) {
      final revision = ++_revision;
      final persisted = await _enqueue(Map<String, String>.of(_pins), revision: revision);
      if (persisted && revision == _revision) return;
    }
  }

  /// Removes the pin from memory before awaiting storage, so a concurrent
  /// in-flight pin commit sees the revision change and cannot overwrite revoke.
  Future<bool> revoke(String fingerprint) async {
    if (!_pins.containsKey(fingerprint)) return false;
    _pins.remove(fingerprint);
    final revision = ++_revision;
    final current = Map<String, String>.of(_pins);
    try {
      final persisted = await _enqueue(current, revision: revision);
      if (persisted) return true;
    } catch (_, stackTrace) {
      if (_revision != revision) {
        Error.throwWithStackTrace(
          StateError('Trust revocation was superseded by a concurrent trust mutation; durable trust may survive restart'),
          stackTrace,
        );
      }
      try {
        final retried = await _enqueue(Map<String, String>.of(_pins), revision: revision);
        if (retried) return true;
      } catch (_) {}
      Error.throwWithStackTrace(
        StateError('Trust revocation could not be persisted after retry; durable trust may survive restart'),
        stackTrace,
      );
    }

    // Never queue an old snapshot after a newer pin/revoke. We cannot claim
    // durable revocation if a concurrent mutation superseded this write.
    throw StateError(
      'Trust revocation was superseded by a concurrent trust mutation; durable trust must be rechecked',
    );
  }

  Future<bool> _enqueue(
    Map<String, String> snapshot, {
    required int revision,
  }) {
    final stable = Map<String, String>.unmodifiable(snapshot);
    final operation = _writeTail.then((_) async {
      // Skip queued snapshots invalidated by a newer mutation. Also report a
      // write as stale if the revision changed while platform storage awaited.
      if (revision != _revision) return false;
      await _writeSnapshot(stable);
      return revision == _revision;
    });
    // Keep the queue usable after a failed write; the individual caller still
    // receives that failure from [operation].
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return operation;
  }
}

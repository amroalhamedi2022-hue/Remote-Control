/// Revokes in-flight pairing work when a listener/session is stopped.
/// A generation token is local-only; it never authorizes remote actions.
class PairingLifecycle {
  int _generation = 0;

  int get ticket => _generation;

  void invalidate() => _generation++;

  bool isCurrent(int ticket) => ticket == _generation;

  void requireCurrent(int ticket) {
    if (!isCurrent(ticket)) {
      throw StateError('Pairing session was stopped');
    }
  }
}

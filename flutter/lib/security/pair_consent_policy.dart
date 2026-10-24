import 'dart:async';

/// Fail-closed, bounded consent for experimental LAN pairing.
/// An unanswered dialog never leaves a socket waiting indefinitely.
/// This is not permission for screen control, audio, files or clipboard.
class PairConsentPolicy {
  static const defaultTimeout = Duration(seconds: 45);

  static Future<bool> awaitApproval(Future<bool> Function() request,
      {Duration timeout = defaultTimeout}) async {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'Must be positive');
    }
    try {
      return await request().timeout(timeout, onTimeout: () => false);
    } catch (_) {
      // UI teardown or platform exceptions must never implicitly approve.
      return false;
    }
  }
}

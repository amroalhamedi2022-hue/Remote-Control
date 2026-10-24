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
    // Future.sync also converts a synchronous dialog exception to a Future.
    // Attach the error handler before the timeout so an immediately failed
    // consent Future cannot escape as an unhandled error in Flutter's test zone.
    return Future<bool>.sync(request)
        .then<bool>((approved) => approved,
            onError: (Object _, StackTrace __) => false)
        .timeout(timeout, onTimeout: () => false);
  }
}

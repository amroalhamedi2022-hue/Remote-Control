import 'clipboard_policy.dart';
import 'pair_consent_policy.dart';

/// One-shot clipboard receive gate shared by the LAN pairing receiver and tests.
/// Discovery labels are never authorization; the caller supplies the authenticated
/// session's lifecycle check and a receiver-local consent callback.
class ClipboardReceivePolicy {
  /// Returns the UTF-8 byte count on success, null on user denial.
  ///
  /// Invalid text is rejected before prompting. Session revocation is checked
  /// before consent, after the asynchronous prompt, and after the platform write.
  /// A platform clipboard write already in progress cannot be rolled back.
  static Future<int?> acceptOnce({
    required String text,
    required bool Function() isSessionActive,
    required Future<bool> Function() requestConsent,
    required Future<void> Function(String text) write,
    Duration consentTimeout = PairConsentPolicy.defaultTimeout,
  }) async {
    final bytes = ClipboardPolicy.validate(text);
    if (!isSessionActive()) {
      throw StateError('Pairing session was stopped');
    }

    final approved = await PairConsentPolicy.awaitApproval(
      requestConsent,
      timeout: consentTimeout,
    );
    if (!approved) return null;
    if (!isSessionActive()) {
      throw StateError('Pairing session was stopped');
    }

    await write(text);
    if (!isSessionActive()) {
      throw StateError('Pairing session was stopped');
    }
    return bytes;
  }
}

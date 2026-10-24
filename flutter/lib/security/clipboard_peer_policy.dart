/// LAN discovery labels are untrusted. Clipboard transfer still requires
/// authenticated pairing and explicit receiver consent on EVERY operation.
/// This allowlist is only a UI routing gate, never a trust decision.
class ClipboardPeerPolicy {
  static bool canSendTo(String platform) =>
      platform == 'Android' || platform == 'Windows';
}

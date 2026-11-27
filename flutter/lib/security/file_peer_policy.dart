/// Discovery labels are untrusted routing hints, not authentication.
/// The signed file intent and fresh receiver consent remain mandatory.
class FilePeerPolicy {
  static bool canSendTo(String platform) =>
      platform == 'Android' || platform == 'Windows';
}

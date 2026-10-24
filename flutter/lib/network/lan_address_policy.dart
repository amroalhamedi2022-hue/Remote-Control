// Explicit IPv4 scope for the experimental LAN-only discovery/pairing paths.
// RFC 1918 private ranges and RFC 3927 IPv4 link-local are allowed.
// Loopback is permitted ONLY for local test/inbound paths when requested.
// Address filtering is defense-in-depth, NOT authentication or proof of same Wi-Fi.
// Never use this to grant screen/input/file permissions without consent.
import 'dart:io';

bool isLocalLanIpv4(InternetAddress? address, {bool allowLoopback = false}) {
  if (address == null || address.type != InternetAddressType.IPv4) return false;
  final bytes = address.rawAddress;
  if (bytes.length != 4) return false;
  final a = bytes[0], b = bytes[1];
  if (allowLoopback && a == 127) return true;
  return a == 10 ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 168) ||
      (a == 169 && b == 254);
}

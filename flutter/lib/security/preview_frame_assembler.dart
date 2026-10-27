import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Validates and assembles one bounded JPEG preview frame at a time.
///
/// The 15-second absolute assembly deadline is independent of the per-message
/// idle timeout. It prevents a LAN peer from keeping a half-built image alive
/// indefinitely by sending one valid part just before each idle timeout.
class PreviewFrameAssembler {
  static const int maxFrameBytes = 512 * 1024;
  // Keep IDs within a signed 31-bit range shared by Dart, Kotlin and Windows
  // native diagnostics. Out-of-range peer values must not poison later frames.
  static const int maxFrameId = 0x7fffffff;
  static const int maxPartBytes = 2600;
  static const int maxEncodedPartChars = 4000;
  static const Duration maxAssemblyTime = Duration(seconds: 15);

  final Stopwatch _clock = Stopwatch()..start();
  final int Function()? _nowMicrosOverride;
  BytesBuilder? _buffer;
  int? _currentId;
  int? _startedAtMicros;
  int _expected = 0;
  int _written = 0;
  int _lastCompletedId = -1;
  int? _lastObservedMicros;
  bool _clockBroken = false;

  PreviewFrameAssembler({int Function()? nowMicros})
      : _nowMicrosOverride = nowMicros;

  int _readNowMicros() {
    if (_clockBroken) {
      throw TimeoutException('Preview monotonic clock is no longer trustworthy');
    }
    late final int now;
    try {
      now = _nowMicrosOverride?.call() ?? _clock.elapsedMicroseconds;
    } catch (_) {
      _clockBroken = true;
      throw TimeoutException('Preview monotonic clock is unavailable');
    }
    final previous = _lastObservedMicros;
    if (now < 0 || (previous != null && now < previous)) {
      _clockBroken = true;
      throw TimeoutException('Preview monotonic clock moved backwards');
    }
    _lastObservedMicros = now;
    return now;
  }

  /// Returns a complete JPEG only for FRAME_END; intermediate messages return null.
  /// A protocol error resets the partial frame before propagating the error.
  Uint8List? accept(Map<String, dynamic> message) {
    try {
      return _accept(message);
    } catch (_) {
      _resetPartial();
      rethrow;
    }
  }

  Uint8List? _accept(Map<String, dynamic> message) {
    switch (message['type']) {
      case 'FRAME_BEGIN':
        if (_buffer != null) {
          throw const FormatException('Overlapping preview frames');
        }
        final id = message['id'];
        final length = message['bytes'];
        if (id is! int || id < 0 || id > maxFrameId || id <= _lastCompletedId ||
            length is! int || length < 4 || length > maxFrameBytes) {
          throw const FormatException('Invalid preview frame header');
        }
        _currentId = id;
        _expected = length;
        _written = 0;
        _startedAtMicros = _readNowMicros();
        _buffer = BytesBuilder(copy: false);
        return null;

      case 'FRAME_PART':
        _checkActiveAndDeadline();
        final encoded = message['data'];
        if (message['id'] != _currentId || message['offset'] != _written ||
            encoded is! String || encoded.isEmpty ||
            encoded.length > maxEncodedPartChars ||
            !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(encoded)) {
          throw const FormatException('Invalid preview part');
        }
        final part = base64Url.decode(base64Url.normalize(encoded));
        if (base64Url.encode(part).replaceAll('=', '') != encoded ||
            part.isEmpty || part.length > maxPartBytes ||
            _written + part.length > _expected) {
          throw const FormatException('Preview frame overflow or non-canonical base64');
        }
        _buffer!.add(part);
        _written += part.length;
        return null;

      case 'FRAME_END':
        _checkActiveAndDeadline();
        if (message['id'] != _currentId || _written != _expected) {
          throw const FormatException('Incomplete preview frame');
        }
        final image = _buffer!.takeBytes();
        if (image.length < 4 || image[0] != 0xff || image[1] != 0xd8 ||
            image[image.length - 2] != 0xff || image.last != 0xd9) {
          throw const FormatException('Not a complete JPEG');
        }
        _lastCompletedId = _currentId!;
        _resetPartial();
        return image;

      default:
        throw StateError('Unexpected preview message');
    }
  }

  void _checkActiveAndDeadline() {
    final started = _startedAtMicros;
    if (_buffer == null || _currentId == null || started == null) {
      throw const FormatException('Preview part without frame header');
    }
    final now = _readNowMicros();
    if (now < started || now - started > maxAssemblyTime.inMicroseconds) {
      throw TimeoutException('Preview frame assembly exceeded 15 seconds');
    }
  }

  void _resetPartial() {
    _buffer = null;
    _currentId = null;
    _startedAtMicros = null;
    _expected = 0;
    _written = 0;
  }
}

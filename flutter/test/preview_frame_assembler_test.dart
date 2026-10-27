import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/security/preview_frame_assembler.dart';

void main() {
  final jpeg = Uint8List.fromList([0xff, 0xd8, 0x21, 0x22, 0xff, 0xd9]);
  String encode(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

  Map<String, dynamic> begin(int id, int bytes) =>
      {'type': 'FRAME_BEGIN', 'id': id, 'bytes': bytes};
  Map<String, dynamic> part(int id, int offset, String data) =>
      {'type': 'FRAME_PART', 'id': id, 'offset': offset, 'data': data};
  Map<String, dynamic> end(int id) => {'type': 'FRAME_END', 'id': id};

  test('assembles a complete JPEG and accepts the next increasing frame id', () {
    final assembler = PreviewFrameAssembler();
    expect(assembler.accept(begin(1, jpeg.length)), isNull);
    expect(assembler.accept(part(1, 0, encode(jpeg))), isNull);
    expect(assembler.accept(end(1)), orderedEquals(jpeg));
    expect(assembler.accept(begin(2, jpeg.length)), isNull);
    expect(assembler.accept(part(2, 0, encode(jpeg))), isNull);
    expect(assembler.accept(end(2)), orderedEquals(jpeg));
  });

  test('rejects a frame whose absolute assembly deadline elapsed', () {
    var now = 100;
    final assembler = PreviewFrameAssembler(nowMicros: () => now);
    assembler.accept(begin(1, jpeg.length));
    now += PreviewFrameAssembler.maxAssemblyTime.inMicroseconds + 1;
    expect(() => assembler.accept(part(1, 0, encode(jpeg))),
        throwsA(isA<TimeoutException>()));
  });

  test('rejects a backwards monotonic frame clock', () {
    var now = 1000;
    final assembler = PreviewFrameAssembler(nowMicros: () => now);
    assembler.accept(begin(1, jpeg.length));
    now = 999;
    expect(() => assembler.accept(part(1, 0, encode(jpeg))),
        throwsA(isA<TimeoutException>()));
  });

  test('rejects overlapping or replayed frame identifiers', () {
    final assembler = PreviewFrameAssembler();
    assembler.accept(begin(1, jpeg.length));
    expect(() => assembler.accept(begin(2, jpeg.length)),
        throwsA(isA<FormatException>()));
    assembler.accept(begin(2, jpeg.length));
    assembler.accept(part(2, 0, encode(jpeg)));
    assembler.accept(end(2));
    expect(() => assembler.accept(begin(2, jpeg.length)),
        throwsA(isA<FormatException>()));
  });

  test('rejects gaps, wrong offsets, non-canonical base64 and oversized parts', () {
    final assembler = PreviewFrameAssembler();
    assembler.accept(begin(1, jpeg.length));
    expect(() => assembler.accept(part(1, 1, encode(jpeg))),
        throwsA(isA<FormatException>()));

    assembler.accept(begin(2, jpeg.length));
    expect(() => assembler.accept(part(2, 0, '${encode(jpeg)}=')),
        throwsA(isA<FormatException>()));

    assembler.accept(begin(3, PreviewFrameAssembler.maxFrameBytes));
    final oversized = Uint8List(PreviewFrameAssembler.maxPartBytes + 1);
    expect(() => assembler.accept(part(3, 0, encode(oversized))),
        throwsA(isA<FormatException>()));
  });

  test('rejects incomplete or non-JPEG frames', () {
    final assembler = PreviewFrameAssembler();
    assembler.accept(begin(1, jpeg.length + 1));
    assembler.accept(part(1, 0, encode(jpeg)));
    expect(() => assembler.accept(end(1)), throwsA(isA<FormatException>()));

    final bad = Uint8List.fromList([1, 2, 3, 4]);
    assembler.accept(begin(2, bad.length));
    assembler.accept(part(2, 0, encode(bad)));
    expect(() => assembler.accept(end(2)), throwsA(isA<FormatException>()));
  });
}

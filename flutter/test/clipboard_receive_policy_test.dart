import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/security/clipboard_receive_policy.dart';

void main() {
  test('approved one-shot receive validates and reports UTF-8 bytes', () async {
    const text = 'مرحبًا 👋';
    var written = '';
    final bytes = await ClipboardReceivePolicy.acceptOnce(
      text: text,
      isSessionActive: () => true,
      requestConsent: () async => true,
      write: (value) async => written = value,
    );
    expect(bytes, utf8.encode(text).length);
    expect(written, text);
  });

  test('denial never writes clipboard contents', () async {
    var writes = 0;
    final bytes = await ClipboardReceivePolicy.acceptOnce(
      text: 'private text',
      isSessionActive: () => true,
      requestConsent: () async => false,
      write: (_) async => writes++,
    );
    expect(bytes, isNull);
    expect(writes, 0);
  });

  test('invalid text is rejected before asking for consent', () async {
    var prompts = 0;
    var writes = 0;
    await expectLater(
      ClipboardReceivePolicy.acceptOnce(
        text: 'filename\u202Eexe',
        isSessionActive: () => true,
        requestConsent: () async { prompts++; return true; },
        write: (_) async => writes++,
      ),
      throwsFormatException,
    );
    expect(prompts, 0);
    expect(writes, 0);
  });

  test('revocation while consent is pending prevents the clipboard write', () async {
    final consent = Completer<bool>();
    var active = true;
    var writes = 0;
    final pending = ClipboardReceivePolicy.acceptOnce(
      text: 'do not publish after revoke',
      isSessionActive: () => active,
      requestConsent: () => consent.future,
      write: (_) async => writes++,
    );

    active = false;
    consent.complete(true);
    await expectLater(pending, throwsA(isA<StateError>()));
    expect(writes, 0);
  });

  test('a revoked session cannot start a consent prompt', () async {
    var prompts = 0;
    var writes = 0;
    await expectLater(
      ClipboardReceivePolicy.acceptOnce(
        text: 'text',
        isSessionActive: () => false,
        requestConsent: () async { prompts++; return true; },
        write: (_) async => writes++,
      ),
      throwsA(isA<StateError>()),
    );
    expect(prompts, 0);
    expect(writes, 0);
  });

  test('platform clipboard write errors propagate without success bytes', () async {
    await expectLater(
      ClipboardReceivePolicy.acceptOnce(
        text: 'text',
        isSessionActive: () => true,
        requestConsent: () async => true,
        write: (_) async => throw StateError('clipboard platform failed'),
      ),
      throwsA(isA<StateError>()),
    );
  });
}

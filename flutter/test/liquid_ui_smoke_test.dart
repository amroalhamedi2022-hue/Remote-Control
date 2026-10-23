import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_remote_control/ui/liquid_theme.dart';

void main() {
  test('Liquid Fusion theme is stable in dark and light', () {
    expect(const LiquidColors(false).text, const Color(0xFFF3F8FF));
    expect(const LiquidColors(true).text, const Color(0xFF102956));
    expect(LiquidColors.aqua, const Color(0xFF24D5ED));
  });

  testWidgets('Liquid Fusion glass button is visible', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: LiquidBackdrop(light: false, child: Center(
        child: GlassPanel(child: LiquidAction(label: 'Devices')),
      )),
    )));
    expect(find.text('Devices'), findsOneWidget);
  });
}

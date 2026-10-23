import 'package:flutter/material.dart';

class LiquidColors {
  static const electric = Color(0xFF277DFF);
  static const aqua = Color(0xFF24D5ED);
  static const violet = Color(0xFF9D61FF);
  static const pink = Color(0xFFF664BB);
  final bool light;
  const LiquidColors(this.light);
  Color get text => light ? const Color(0xFF102956) : const Color(0xFFF3F8FF);
  Color get muted => light ? const Color(0xFF4B6A91) : const Color(0xFFA5B7D6);
  Color get panel => light ? const Color(0xE3E7F7FF) : const Color(0xCB102550);
  Color get panelDark => light ? const Color(0xE3D7EDFB) : const Color(0xC40C1A3D);
  Color get border => light ? const Color(0x663D9CD6) : const Color(0x77548DEB);
  Color get selected => light ? const Color(0xFF167DE2) : const Color(0xFF197DEB);
}

class LiquidBackdrop extends StatelessWidget {
  final bool light;
  final Widget child;
  const LiquidBackdrop({super.key, required this.light, required this.child});
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _LiquidPainter(light)))),
      child,
    ],
  );
}

class _LiquidPainter extends CustomPainter {
  final bool light;
  _LiquidPainter(this.light);
  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..shader = LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: light ? const [Color(0xFFF1FBFF), Color(0xFFCEECFC), Color(0xFFE8DBFF)]
                   : const [Color(0xFF071126), Color(0xFF11183E), Color(0xFF0B122C)],
    ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, base);
    void glow(Offset center, double radius, Color tint) {
      final p = Paint()..shader = RadialGradient(colors: [tint, tint.withValues(alpha: 0)])
          .createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, p);
    }
    glow(Offset(size.width * .02, size.height * .88), size.width * .40,
        light ? const Color(0x4485DFF9) : const Color(0x655B45FF));
    glow(Offset(size.width * .98, size.height * .12), size.width * .36,
        light ? const Color(0x44C69DF7) : const Color(0x773A2DD7));
    glow(Offset(size.width * .78, size.height * 1.01), size.width * .29,
        const Color(0x44E63BAE));
    for (final bubble in <(double, double, double)>[(.04,.20,52),(.96,.64,36),(.12,.94,76)]) {
      final center = Offset(size.width * bubble.$1, size.height * bubble.$2);
      final rect = Rect.fromCircle(center: center, radius: bubble.$3);
      canvas.drawCircle(center, bubble.$3, Paint()..shader = RadialGradient(
        center: const Alignment(-.4,-.6), radius: .95,
        colors: [const Color(0x55C4F9FF), const Color(0x226679F8), const Color(0x55962BF3)],
      ).createShader(rect));
      canvas.drawCircle(center, bubble.$3, Paint()..style = PaintingStyle.stroke
        ..strokeWidth = 1.2..color = const Color(0x8895DFFF));
    }
  }
  @override
  bool shouldRepaint(covariant _LiquidPainter oldDelegate) => oldDelegate.light != light;
}

class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final bool strong;
  final double radius;
  const GlassPanel({super.key, required this.child,
    this.padding = const EdgeInsets.all(14), this.strong = false, this.radius = 15});
  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final c = LiquidColors(light);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [strong ? c.panel : c.panelDark, c.panelDark]),
        border: Border.all(color: c.border, width: 1),
        boxShadow: [BoxShadow(color: (light ? Colors.blue : Colors.black).withValues(alpha: .09),blurRadius: 16,offset: const Offset(0,5))],
      ), child: child,
    );
  }
}

class LiquidAction extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool active;
  final bool danger;
  final bool gradient;
  const LiquidAction({super.key,required this.label,this.icon,this.onTap,
    this.active=false,this.danger=false,this.gradient=false});
  @override
  Widget build(BuildContext context) {
    final c = LiquidColors(Theme.of(context).brightness == Brightness.light);
    final selected = active || danger || gradient;
    return Material(color: Colors.transparent,child: InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(9),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11,vertical: 12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(9),
          gradient: selected ? LinearGradient(colors: danger
            ? const [Color(0xFFFF347D),Color(0xFFBD2368)]
            : gradient ? const [Color(0xFF159AF4),Color(0xFF5566F7),Color(0xFFAF50E0)]
            : const [Color(0xFF068EDB),Color(0xFF386BEC)]) : null,
          color: selected ? null : c.panel,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min,
          children: [if(icon!=null)...[Icon(icon,size:16,color:selected?Colors.white:c.text),const SizedBox(width:7)],
            Flexible(child:Text(label,overflow:TextOverflow.ellipsis,style:TextStyle(color:selected?Colors.white:c.text,fontSize:12,fontWeight:FontWeight.w700)))],
        ),
      ),
    ));
  }
}

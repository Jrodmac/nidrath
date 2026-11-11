import 'dart:math';

import 'package:flutter/material.dart';

/// Aspecto de una figura humana dibujada con formas suaves (sin píxeles).
class FigureLook {
  final Color skin, hair, top, sleeve, shirt, pants, shoes;
  final Color? tie;
  final bool glasses, bald, cap, face, knife, stains;

  /// Anchura relativa: el carnicero es mucho más ancho que un sicario.
  final double bulk;

  const FigureLook({
    this.skin = const Color(0xFFC08A5E),
    this.hair = const Color(0xFF14110F),
    this.top = const Color(0xFF2A2A33),
    this.sleeve = const Color(0xFF1F1F27),
    this.shirt = const Color(0xFFDADADA),
    this.pants = const Color(0xFF1C1C22),
    this.shoes = const Color(0xFF0B0B0D),
    this.tie,
    this.glasses = false,
    this.bald = false,
    this.cap = false,
    this.face = true,
    this.knife = false,
    this.stains = false,
    this.bulk = 1,
  });
}

/// Traje negro, calvo, chaqueta de cuero y chándal con gorra roja.
const thugFigures = [
  FigureLook(tie: Color(0xFF9A1414), glasses: true),
  FigureLook(tie: Color(0xFF9A1414), glasses: true, bald: true),
  FigureLook(
    hair: Color(0xFF2A1A10),
    top: Color(0xFF5E3D26),
    sleeve: Color(0xFF4A2E1C),
    shirt: Color(0xFF8A8070),
    glasses: true,
  ),
  FigureLook(
    hair: Color(0xFF8A1818),
    top: Color(0xFF2E4066),
    sleeve: Color(0xFF22304E),
    shirt: Color(0xFFDDDDDD),
    cap: true,
    glasses: true,
  ),
];

const bossFigure = FigureLook(
  skin: Color(0xFFC88A62),
  top: Color(0xFFBDB6A2),
  sleeve: Color(0xFFB07850),
  shirt: Color(0xFFBDB6A2),
  pants: Color(0xFF2A2620),
  shoes: Color(0xFF140E0A),
  bald: true,
  knife: true,
  stains: true,
  bulk: 1.4,
);

const mannequinFigure = FigureLook(
  skin: Color(0xFFD8CBB0),
  top: Color(0xFFD0C3A8),
  sleeve: Color(0xFFBDB093),
  shirt: Color(0xFFD0C3A8),
  pants: Color(0xFFC4B79B),
  shoes: Color(0xFFB3A68A),
  bald: true,
  face: false,
);

/// Dibuja una persona de pie con los pies en [feet] y [h] píxeles de alto.
///
/// [facing] sigue el convenio de la vista: seno positivo es de frente, negativo
/// de espaldas, y si domina el coseno va de perfil (hacia la derecha si es
/// positivo). [swing] (-1..1) es el punto del paso; [tint] es la luz que le da.
void drawFigure(
  Canvas canvas,
  Offset feet,
  double h,
  FigureLook k, {
  required double facing,
  double swing = 0,
  Color tint = const Color(0xFFFFFFFF),
  double opacity = 1,
  double rot = 0,
  bool aiming = false,
}) {
  final ca = cos(facing), sa = sin(facing);
  final side = ca.abs() > sa.abs();
  final front = !side && sa > 0;
  final paint = Paint();
  Color lit(Color c, [double m = 1]) => Color.from(
        alpha: 1,
        red: (c.r * tint.r * m).clamp(0.0, 1.0),
        green: (c.g * tint.g * m).clamp(0.0, 1.0),
        blue: (c.b * tint.b * m).clamp(0.0, 1.0),
      );
  void rr(double l, double t, double r, double b, double rad, Color c, [double m = 1]) =>
      canvas.drawRRect(RRect.fromLTRBR(l, t, r, b, Radius.circular(rad)), paint..color = lit(c, m));
  void dot(double x, double y, double r, Color c) => canvas.drawCircle(Offset(x, y), r, paint..color = lit(c));

  canvas.save();
  if (opacity < 1) {
    canvas.saveLayer(Rect.fromCircle(center: feet, radius: h * 1.5),
        Paint()..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0)));
  }
  canvas.translate(feet.dx, feet.dy);
  if (rot != 0) canvas.rotate(rot);
  canvas.scale(h * k.bulk * (side && ca < 0 ? -1 : 1), h);

  const head = Rect.fromLTRB(-0.07, -0.985, 0.07, -0.825);
  const steel = Color(0xFFD0D4D8), gunmetal = Color(0xFF15151A);

  if (side) {
    final a = swing * 0.5;
    void leg(double ang, double m) {
      canvas.save();
      canvas.translate(0, -0.48);
      canvas.rotate(ang);
      rr(-0.052, 0, 0.052, 0.45, 0.03, k.pants, m);
      rr(-0.052, 0.42, 0.095, 0.48, 0.022, k.shoes);
      canvas.restore();
    }

    leg(-a, 0.75);
    leg(a, 1);
    rr(-0.1, -0.83, 0.1, -0.45, 0.055, k.top);
    rr(-0.03, -0.86, 0.04, -0.8, 0.01, k.skin, 0.85);
    canvas.drawOval(head.shift(const Offset(0.012, 0)), paint..color = lit(k.skin));
    dot(0.084, -0.895, 0.013, k.skin);
    if (!k.bald) {
      canvas.drawArc(head.shift(const Offset(0.006, -0.004)).inflate(0.006), pi * 0.72, pi * 0.98, false,
          paint..color = lit(k.hair));
    }
    if (k.cap) rr(0.03, -0.962, 0.135, -0.94, 0.01, k.hair);
    if (k.glasses) {
      rr(0.025, -0.93, 0.086, -0.9, 0.008, const Color(0xFF050505));
    } else if (k.face) {
      dot(0.055, -0.915, 0.009, const Color(0xFF100808));
    }
    // El brazo: colgando, o extendido al apuntar.
    canvas.save();
    canvas.translate(0.005, -0.78);
    canvas.rotate(aiming ? -pi / 2 : -a * 0.9);
    if (aiming) rr(-0.035, 0.35, 0.02, 0.48, 0.01, gunmetal);
    if (k.knife) rr(-0.014, 0.35, 0.022, 0.58, 0.006, steel);
    rr(-0.042, -0.02, 0.042, 0.33, 0.038, k.sleeve);
    dot(0, 0.345, 0.033, k.skin);
    canvas.restore();
  } else {
    for (final s in const [-1.0, 1.0]) {
      final up = max(0.0, s * swing) * 0.05;
      rr(s > 0 ? 0.012 : -0.125, -0.5, s > 0 ? 0.125 : -0.012, -0.03 - up, 0.03, k.pants);
      rr(s > 0 ? 0.008 : -0.135, -0.065 - up, s > 0 ? 0.135 : -0.008, -up, 0.022, k.shoes);
    }
    for (final s in const [-1.0, 1.0]) {
      final sw = -s * swing * 0.03;
      rr(s > 0 ? 0.145 : -0.235, -0.81, s > 0 ? 0.235 : -0.145, -0.46 + sw, 0.04, k.sleeve);
      dot(s * 0.195, -0.44 + sw, 0.033, k.skin);
    }
    if (k.knife) rr(0.185, -0.66, 0.215, -0.45, 0.006, steel);
    rr(-0.17, -0.835, 0.17, -0.45, 0.06, k.top);
    rr(-0.032, -0.86, 0.032, -0.8, 0.01, k.skin, 0.85);
    if (front) {
      canvas.drawPath(
          Path()
            ..moveTo(-0.05, -0.835)
            ..lineTo(0.05, -0.835)
            ..lineTo(0, -0.67)
            ..close(),
          paint..color = lit(k.shirt));
      final tie = k.tie;
      if (tie != null) {
        canvas.drawPath(
            Path()
              ..moveTo(-0.014, -0.83)
              ..lineTo(0.014, -0.83)
              ..lineTo(0.02, -0.7)
              ..lineTo(0, -0.67)
              ..lineTo(-0.02, -0.7)
              ..close(),
            paint..color = lit(tie));
      }
      if (k.stains) {
        dot(-0.06, -0.62, 0.035, const Color(0xFF8A0E0E));
        dot(0.05, -0.54, 0.028, const Color(0xFF8A0E0E));
        dot(0.02, -0.7, 0.018, const Color(0xFF8A0E0E));
      }
      if (aiming) {
        dot(0.05, -0.66, 0.04, k.skin);
        dot(0.05, -0.66, 0.026, gunmetal);
      }
    }
    canvas.drawOval(head, paint..color = lit(front || k.bald ? k.skin : k.hair, front ? 1 : 0.9));
    if (front) {
      if (!k.bald) canvas.drawArc(head.inflate(0.005), pi + 0.25, pi - 0.5, false, paint..color = lit(k.hair));
      if (k.glasses) {
        rr(-0.062, -0.93, 0.062, -0.9, 0.01, const Color(0xFF050505));
      } else if (k.face) {
        dot(-0.028, -0.915, 0.009, const Color(0xFF100808));
        dot(0.028, -0.915, 0.009, const Color(0xFF100808));
      }
      if (k.face) rr(-0.02, -0.868, 0.02, -0.86, 0.004, const Color(0xFF5A2A20));
    }
    if (k.cap) {
      canvas.drawArc(head.inflate(0.006), pi + 0.1, pi - 0.2, false, paint..color = lit(k.hair));
      if (front) rr(-0.078, -0.948, 0.078, -0.93, 0.008, k.hair, 0.8);
    }
  }

  if (opacity < 1) canvas.restore();
  canvas.restore();
}

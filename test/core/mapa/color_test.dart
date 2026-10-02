// =============================================================================
// color_test.dart
// Test de la extensión `aCss`.
//
// No es un test decorativo: la extensión convierte `Color` de Flutter a string
// CSS para MapLibre. Si el cálculo del hex falla, los marcadores se dibujan con
// colores equivocados o invisibles y NO hay ningún error del compilador.
//
// Copiar a:  test/core/mapa/color_test.dart
// Ejecutar:   flutter test
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:autofix/theme/app_colors.dart';
import 'package:autofix/screens/cliente/talleres_mapa_screen.dart';

void main() {
  group('ColorMapa.aCss', () {
    test('convierte los colores de AppColors a hex mayúsculas', () {
      expect(AppColors.blueAccent.aCss, '#3B82F6');
      expect(AppColors.orangePrimary.aCss, '#F07A22');
      expect(AppColors.headerNavy.aCss, '#0B1E3F');
    });

    test('el blanco puro no se rompe', () {
      expect(AppColors.cardWhite.aCss, '#FFFFFF');
    });

    test('siempre devuelve 7 caracteres (# + 6 hex)', () {
      // Un hex mal formado hace que MapLibre ignore el color en silencio.
      for (final c in [
        AppColors.background,
        AppColors.textGray,
        AppColors.greenAccent,
        AppColors.atrasadas,
      ]) {
        expect(c.aCss.length, 7, reason: 'color inválido: ${c.aCss}');
        expect(c.aCss, matches(RegExp(r'^#[0-9A-F]{6}$')));
      }
    });
  });
}

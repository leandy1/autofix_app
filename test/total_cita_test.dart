// =============================================================================
// total_cita_test.dart
// Tests del calculo de `citas.total` y del formato de precios del formulario.
//
// Por que estan en un archivo propio: `total` es el unico numero que la app le
// enseña al cliente y despues le muestra a un tecnico. Si la suma sale mal, no
// hay crash ni error de compilacion: hay una cita que dice 1,250 cuando queria
// 1,450, y el error se descubre cuando el cliente llega a pagar.
//
// La aritmetica va en `TipoServicio.totalDe` y no en el widget a proposito, asi
// que acá se puede verificar sin montar el formulario.
// Ejecutar:   flutter test test/total_cita_test.dart
// =============================================================================

import 'package:autofix/features/configuracion/models/tipo_servicio.dart';
import 'package:autofix/screens/cliente/agendar_cita_cliente_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final catalogo = <TipoServicio>[
    const TipoServicio(nombre: 'Cambio de aceite y filtro', precio: 1850),
    const TipoServicio(nombre: 'Frenos', precio: 3200),
    const TipoServicio(nombre: 'Suspensión y dirección', precio: 2750),
    const TipoServicio(nombre: 'Alineación y balanceo', precio: 1500),
  ];

  group('TipoServicio.totalDe', () {
    test('suma los precios de los servicios marcados', () {
      final total = TipoServicio.totalDe(catalogo, {'Frenos', 'Alineación y balanceo'});

      // 3200 + 1500
      expect(total, 4700);
    });

    test('suma tres y da el mismo que de a dos', () {
      // La comprobacion que atrapa el error de sumar el ultimo dos veces.
      expect(
        TipoServicio.totalDe(
          catalogo,
          {'Frenos', 'Alineación y balanceo', 'Cambio de aceite y filtro'},
        ),
        3200 + 1500 + 1850,
      );
    });

    test('sin servicios marcados da 0', () {
      expect(TipoServicio.totalDe(catalogo, const <String>{}), 0);
    });

    test('catalogo vacio da 0 y no revienta', () {
      // Puede pasar si el admin borro todos los servicios: el formulario tiene
      // que poder seguir guardando citas sin servicios.
      expect(
        TipoServicio.totalDe(const <TipoServicio>[], {'Frenos'}),
        0,
      );
    });

    test('un nombre que no esta en el catalogo cuenta 0 y NO lanza', () {
      // El caso real: el cliente abre el formulario, el admin agrega un servicio
      // nuevo, el cliente guarda. El nombre guardado no esta en el catalogo que
      // se cargo. Romperle el envio por un dato de precio es peor que dejar un
      // total subestimado.
      expect(
        TipoServicio.totalDe(catalogo, {'Frenos', 'Servicio Inventado'}),
        3200,
      );
    });

    test('los nombres con acentos se cruzan bien', () {
      // El formulario manda el NOMBRE que veio del catalogo, con su tilde. Si
      // el cruce se hiciera normalizado de mas o de menos, estos servicios no
      // se sumado nunca y el total daria 0 sin error visible.
      expect(
        TipoServicio.totalDe(catalogo, {'Suspensión y dirección'}),
        2750,
      );
    });

    test('un servicio con precio 0 no suma, y no es un error', () {
      // La semilla los siembra en 0 a proposito. El total de una cita con esos
      // servicios marcados es 0, y ese 0 es el dato correcto.
      final enCero = <TipoServicio>[
        const TipoServicio(nombre: 'Cambio de aceite y filtro', precio: 0),
      ];

      expect(TipoServicio.totalDe(enCero, {'Cambio de aceite y filtro'}), 0);
    });

    test('el total nunca es negativo', () {
      // `precio` no tiene CHECK en la base, asi que un -500 se podria guardar a
      // mano. Un total negativo en pantalla es peor que uno mal: parece una
      // deuda.
      final negativo = <TipoServicio>[
        const TipoServicio(nombre: 'Error de carga', precio: -500),
      ];

      final total = TipoServicio.totalDe(negativo, {'Error de carga'});
      expect(total, 0, reason: 'no se muestra un total negativo al cliente');
    });

    test('el resultado es un entero, sin decimales', () {
      // `precio` es `int` a proposito: con REAL, 1250.50 vuelve como
      // 1250.4999999 y la suma de una lista deja de cuadrar con el total.
      final total = TipoServicio.totalDe(catalogo, {'Frenos', 'Alineación y balanceo'});

      expect(total, isA<int>());
      expect(total, 4700);
    });

    test('un Set no cuenta dos veces el mismo servicio', () {
      // `_serviciosSeleccionados` es un `Set`, no una lista: marcar la misma
      // casilla dos veces no puede duplicar el cobro. Este test lo deja fijo,
      // porque cambiar el `Set` por una `List` sin querer es el error mas
      // silencioso que hay en un formulario de cobro.
      //
      // El duplicado va en una lista y no en el literal del set a proposito:
      // escribirlo en el set seria un error de compilacion, y lo que se quiere
      // probar es justamente que el `Set` lo traga sin duplicar el cobro.
      final marcados = <String>{...['Frenos', 'Frenos']};

      expect(marcados.length, 1);
      expect(TipoServicio.totalDe(catalogo, marcados), 3200);
    });
  });

  group('formatearPesosDR', () {
    test('pone el simbolo y el separador de miles', () {
      expect(formatearPesosDR(0), 'RD\$ 0');
      expect(formatearPesosDR(500), 'RD\$ 500');
      expect(formatearPesosDR(1850), 'RD\$ 1,850');
      expect(formatearPesosDR(1250000), 'RD\$ 1,250,000');
    });

    test('un numero de tres digitos NO lleva separador', () {
      // El error clasico de "poner la coma donde no va". "RD$ 1,000" lo leeria
      // el cliente como mil, y lo que vale es diez mil.
      expect(formatearPesosDR(999), 'RD\$ 999');
      expect(formatearPesosDR(100), 'RD\$ 100');
    });

    test('los miles exactos llevan coma y no punto', () {
      expect(formatearPesosDR(1000), 'RD\$ 1,000');
      expect(formatearPesosDR(1000000), 'RD\$ 1,000,000');
    });

    test('un precio negativo no rompe el formato', () {
      // No debería pasar (ver el test del total), pero si alguien carga un
      // precio negativo el formateador tiene que devolver algo y no reventar la
      // pantalla de Configuración.
      expect(formatearPesosDR(-1500), contains('1,500'));
    });
  });

  group('etiquetaPrecio', () {
    test('con precio cargado muestra el monto', () {
      expect(etiquetaPrecio(1850), 'RD\$ 1,850');
    });

    test('con precio 0 dice "Precio por definir", NO "RD\$ 0"', () {
      // "RD$ 0" es una afirmación sobre el taller: dice que el trabajo es gratis.
      // La verdad es que nadie lo ha cargado todavía. Son dos verdades distintas
      // y el cliente tiene que ver la segunda.
      expect(etiquetaPrecio(0), 'Precio por definir');
      expect(etiquetaPrecio(0), isNot(contains('RD\$')));
    });
  });
}
import 'package:flutter/widgets.dart';

import '../connectivity/connectivity_service.dart';

/// Inyecta el [ConnectivityService] en el arbol de widgets.
///
/// [InheritedNotifier] reconstruye unicamente a los descendientes que dependen
/// de el (el banner), no a toda la app, cuando el estado de red cambia.
class ConnectivityScope extends InheritedNotifier<ConnectivityService> {
  const ConnectivityScope({
    required ConnectivityService servicio,
    required super.child,
    super.key,
  }) : super(notifier: servicio);

  static ConnectivityService of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ConnectivityScope>();
    assert(scope?.notifier != null, 'ConectivityScope no encontrado en el arbol.');
    return scope!.notifier!;
  }

  static ConnectivityService read(BuildContext context) {
    final element = context.getElementForInheritedWidgetOfExactType<ConnectivityScope>();
    final scope = element?.widget as ConnectivityScope?;
    assert(scope?.notifier != null, 'ConectivityScope no encontrado en el arbol.');
    return scope!.notifier!;
  }
}

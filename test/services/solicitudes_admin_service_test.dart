import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../lib/models/solicitud_admin.dart';
import '../../lib/services/solicitudes_admin_service.dart';

void main() {
  group('SolicitudesAdminService', () {
    test('carga solicitudes iniciales', () {
      final service = SolicitudesAdminService();

      expect(service.solicitudes.length, 1);
      expect(service.solicitudes.first.cliente, 'María Pérez');
      expect(service.solicitudes.first.marcaVehiculo, 'Honda');
      expect(service.solicitudes.first.modeloVehiculo, 'Civic');
      expect(service.solicitudes.first.anioVehiculo, 2021);
      expect(service.solicitudes.first.placa, 'A456789');
      expect(
        service.solicitudes.first.estado,
        EstadoSolicitudAdmin.nueva,
      );
    });

    test('aceptar mueve la solicitud a Pendiente', () {
      final service = SolicitudesAdminService();

      final resultado = service.aceptarSolicitud(1);

      expect(resultado, isTrue);
      expect(
        service.obtenerPorId(1)?.estado,
        EstadoSolicitudAdmin.pendiente,
      );
      expect(service.nuevas, isEmpty);
      expect(service.pendientes.length, 1);
      expect(service.enProceso, isEmpty);
    });

    test('rechazar cambia la solicitud a rechazada', () {
      final service = SolicitudesAdminService();

      final resultado = service.rechazarSolicitud(1);

      expect(resultado, isTrue);
      expect(
        service.obtenerPorId(1)?.estado,
        EstadoSolicitudAdmin.rechazada,
      );
      expect(service.pendientes, isEmpty);
    });

    test('proponer una nueva fecha y hora', () {
      final service = SolicitudesAdminService();

      final nuevaFecha = DateTime(2026, 10, 15);
      const nuevaHora = TimeOfDay(hour: 14, minute: 30);

      final resultado = service.proponerFechaHora(
        1,
        fecha: nuevaFecha,
        hora: nuevaHora,
      );

      final solicitud = service.obtenerPorId(1);

      expect(resultado, isTrue);
      expect(solicitud?.fecha, nuevaFecha);
      expect(solicitud?.hora, nuevaHora);
      expect(
        solicitud?.estado,
        EstadoSolicitudAdmin.fechaPropuesta,
      );
      expect(service.pendientes.length, 1);
    });

    test('completar mueve una solicitud de En proceso a Completada', () {
      final service = SolicitudesAdminService();

      service.aceptarSolicitud(1);

      final resultado = service.completarSolicitud(1);

      expect(resultado, isTrue);
      expect(
        service.obtenerPorId(1)?.estado,
        EstadoSolicitudAdmin.completada,
      );
      expect(service.enProceso, isEmpty);
      expect(service.completadas.length, 1);
    });

    test('crear una nueva solicitud con estado seleccionado', () {
      final service = SolicitudesAdminService();

      final solicitud = service.agregarSolicitud(
        cliente: 'Juan Rodríguez',
        telefono: '809-555-0100',
        taller: 'AutoFix Central',
        marcaVehiculo: 'Toyota',
        modeloVehiculo: 'Corolla',
        anioVehiculo: 2022,
        placa: 'B123456',
        servicios: const [
          'Cambio de aceite',
          'Revisión general',
        ],
        fecha: DateTime(2026, 10, 20),
        hora: const TimeOfDay(hour: 9, minute: 30),
        descripcion: 'Mantenimiento preventivo.',
        estado: EstadoSolicitudAdmin.esperandoPieza,
      );

      expect(solicitud.id, 2);
      expect(solicitud.cliente, 'Juan Rodríguez');
      expect(solicitud.marcaVehiculo, 'Toyota');
      expect(solicitud.modeloVehiculo, 'Corolla');
      expect(solicitud.anioVehiculo, 2022);
      expect(solicitud.placa, 'B123456');
      expect(
        solicitud.estado,
        EstadoSolicitudAdmin.esperandoPieza,
      );
      expect(service.esperandoPieza.length, 1);
    });

    test('cambiar estado mueve la solicitud a la sección correspondiente', () {
      final service = SolicitudesAdminService();

      service.cambiarEstado(
        1,
        EstadoSolicitudAdmin.atrasada,
      );

      expect(service.pendientes, isEmpty);
      expect(service.atrasadas.length, 1);

      service.cambiarEstado(
        1,
        EstadoSolicitudAdmin.completada,
      );

      expect(service.atrasadas, isEmpty);
      expect(service.completadas.length, 1);
    });

    test('devuelve false para una solicitud inexistente', () {
      final service = SolicitudesAdminService();

      expect(service.aceptarSolicitud(999), isFalse);
      expect(service.rechazarSolicitud(999), isFalse);
      expect(service.completarSolicitud(999), isFalse);

      expect(
        service.cambiarEstado(
          999,
          EstadoSolicitudAdmin.enProceso,
        ),
        isFalse,
      );

      expect(
        service.proponerFechaHora(
          999,
          fecha: DateTime(2026, 10, 20),
          hora: const TimeOfDay(hour: 9, minute: 0),
        ),
        isFalse,
      );
    });

    test('los estados tienen sus listas separadas', () {
      final service = SolicitudesAdminService();

      service.agregarSolicitud(
        cliente: 'Cliente Esperando',
        telefono: '809-555-0101',
        taller: 'AutoFix Central',
        marcaVehiculo: 'Honda',
        modeloVehiculo: 'Accord',
        anioVehiculo: 2020,
        placa: 'C111111',
        servicios: const ['Frenos'],
        fecha: DateTime(2026, 10, 21),
        hora: const TimeOfDay(hour: 10, minute: 0),
        descripcion: 'Revisión de frenos.',
        estado: EstadoSolicitudAdmin.esperandoPieza,
      );

      service.agregarSolicitud(
        cliente: 'Cliente Proceso',
        telefono: '809-555-0102',
        taller: 'AutoFix Central',
        marcaVehiculo: 'Ford',
        modeloVehiculo: 'Focus',
        anioVehiculo: 2019,
        placa: 'C222222',
        servicios: const ['Motor'],
        fecha: DateTime(2026, 10, 22),
        hora: const TimeOfDay(hour: 11, minute: 0),
        descripcion: 'Revisión de motor.',
        estado: EstadoSolicitudAdmin.enProceso,
      );

      service.agregarSolicitud(
        cliente: 'Cliente Atrasado',
        telefono: '809-555-0103',
        taller: 'AutoFix Central',
        marcaVehiculo: 'Hyundai',
        modeloVehiculo: 'Elantra',
        anioVehiculo: 2021,
        placa: 'C333333',
        servicios: const ['Diagnóstico'],
        fecha: DateTime(2026, 10, 23),
        hora: const TimeOfDay(hour: 12, minute: 0),
        descripcion: 'Diagnóstico general.',
        estado: EstadoSolicitudAdmin.atrasada,
      );

      service.agregarSolicitud(
        cliente: 'Cliente Completado',
        telefono: '809-555-0104',
        taller: 'AutoFix Central',
        marcaVehiculo: 'Suzuki',
        modeloVehiculo: 'Swift',
        anioVehiculo: 2020,
        placa: 'C444444',
        servicios: const ['Aire acondicionado'],
        fecha: DateTime(2026, 10, 24),
        hora: const TimeOfDay(hour: 13, minute: 0),
        descripcion: 'Revisión de aire acondicionado.',
        estado: EstadoSolicitudAdmin.completada,
      );

      expect(service.esperandoPieza.length, 1);
      expect(service.enProceso.length, 1);
      expect(service.atrasadas.length, 1);
      expect(service.completadas.length, 1);
    });
  });
}

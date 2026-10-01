import 'package:flutter/material.dart';

import 'package:autofix/features/auth/screens/login_screen.dart';
import 'package:autofix/shared/theme/app_colors.dart';
import 'agendar_cita_cliente_section.dart';
import 'mis_citas_cliente_section.dart';
import 'talleres_cliente_section.dart';

class DashboardClienteScreen extends StatefulWidget {
  const DashboardClienteScreen({super.key});

  @override
  State<DashboardClienteScreen> createState() => _DashboardClienteScreenState();
}

class _DashboardClienteScreenState extends State<DashboardClienteScreen> {
  int _selectedSection = 0;
  String _selectedWorkshop = 'AutoFix Central';

  static const _sectionTitles = [
    'Talleres cercanos',
    'Agendar cita',
    'Mis citas',
  ];

  void _changeSection(int index) {
    setState(() => _selectedSection = index);
  }

  void _selectWorkshop(String workshop) {
    setState(() {
      _selectedWorkshop = workshop;
      _selectedSection = 1;
    });
  }

  void _cerrarSesion() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.headerNavy,
        foregroundColor: Colors.white,
        titleSpacing: 20,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'AutoFix',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            Text(
              _sectionTitles[_selectedSection],
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: _cerrarSesion,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.025, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(_selectedSection),
                child: switch (_selectedSection) {
                  0 => TalleresClienteSection(
                    tallerSeleccionado: _selectedWorkshop,
                    onTallerSelected: _selectWorkshop,
                  ),
                  1 => AgendarCitaClienteSection(
                    tallerSeleccionado: _selectedWorkshop,
                    onTallerSelected: (taller) {
                      setState(() => _selectedWorkshop = taller);
                    },
                  ),
                  _ => const MisCitasClienteSection(),
                },
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedSection,
        onDestinationSelected: _changeSection,
        backgroundColor: AppColors.cardWhite,
        indicatorColor: AppColors.orangePrimary.withValues(alpha: 0.14),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined),
            selectedIcon: Icon(Icons.location_on),
            label: 'Talleres',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Agendar',
          ),
          NavigationDestination(
            icon: Icon(Icons.confirmation_number_outlined),
            selectedIcon: Icon(Icons.confirmation_number),
            label: 'Mis citas',
          ),
        ],
      ),
    );
  }
}

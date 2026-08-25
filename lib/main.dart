import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'core/di/service_locator.dart';
import 'core/localization/app_locale.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/bloc/auth_bloc.dart';
import 'features/auth/pages/login_page.dart';
import 'features/tasks/bloc/task_bloc.dart';
import 'features/tasks/pages/task_list_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLocaleController.instance.initialize();
  await appThemeController.initialize();
  await setupServiceLocator();
  runApp(const WorkshopMechanicApp());
}

class WorkshopMechanicApp extends StatelessWidget {
  const WorkshopMechanicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuthBloc>(
      create: (_) => sl<AuthBloc>()..add(CheckAuthStatus()),
      child: AppLanguageScope(
        controller: AppLocaleController.instance,
        child: ValueListenableBuilder<String>(
          valueListenable: AppLocaleController.instance,
          builder: (context, language, _) => ValueListenableBuilder<ThemeMode>(
            valueListenable: appThemeController,
            builder: (context, themeMode, _) => MaterialApp(
              title: AppStrings.translate('workshop'),
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: themeMode,
              themeAnimationDuration: const Duration(milliseconds: 220),
              locale:
                  language == 'am' ? const Locale('am') : const Locale('en'),
              supportedLocales: const [Locale('en'), Locale('am')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: BlocBuilder<AuthBloc, AuthState>(
                builder: (ctx, state) {
                  if (state is AuthAuthenticated) {
                    return BlocProvider(
                      create: (_) => sl<TaskBloc>()..add(const LoadTasks()),
                      child: const LocationGate(child: TaskListPage()),
                    );
                  }
                  return const LoginPage();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LocationGate extends StatefulWidget {
  final Widget child;
  const LocationGate({super.key, required this.child});
  @override
  State<LocationGate> createState() => _LocationGateState();
}

class _LocationGateState extends State<LocationGate>
    with WidgetsBindingObserver {
  bool _ready = false;
  bool _checking = true;
  bool _openedSettingsAutomatically = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (!mounted) return;
    setState(() => _checking = true);
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied)
      permission = await Geolocator.requestPermission();
    final enabled = await Geolocator.isLocationServiceEnabled();
    final granted = permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
    final accuracy = granted ? await Geolocator.getLocationAccuracy() : null;
    if (mounted)
      setState(() {
        _ready =
            enabled && granted && accuracy != LocationAccuracyStatus.reduced;
        _checking = false;
      });

    // The OS owns these settings, so we cannot switch them on silently. Open
    // the exact system screen automatically once to guide non-technical users.
    if (!_ready && !_openedSettingsAutomatically) {
      _openedSettingsAutomatically = true;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (enabled && granted && accuracy == LocationAccuracyStatus.reduced) {
        await Geolocator.openAppSettings();
      } else if (!enabled) {
        await Geolocator.openLocationSettings();
      } else if (!granted) {
        await Geolocator.openAppSettings();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    if (_checking) {
      return Scaffold(
        backgroundColor: context.appColors.background,
        body: Center(
          child: CircularProgressIndicator(
            color: context.appColors.primary,
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: context.appColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: context.appColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.location_on_rounded,
                  size: 42,
                  color: context.appColors.primary,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Precise Location Required',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'To accurately log duty check-ins and field work, the app requires Precise Location access.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: context.appColors.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 28),

              // Step-by-step guide container
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.appColors.surfaceHigh,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.appColors.border),
                ),
                child: Column(
                  children: [
                    _buildStepRow(
                      number: '1',
                      title: 'Tap "Open App Settings" below',
                    ),
                    const Divider(height: 20),
                    _buildStepRow(
                      number: '2',
                      title: 'Tap Permissions → Location',
                    ),
                    const Divider(height: 20),
                    _buildStepRow(
                      number: '3',
                      title: 'Enable "Use Precise Location" toggle',
                    ),
                  ],
                ),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: context.appColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _checking
                      ? null
                      : () async {
                          await Geolocator.openAppSettings();
                          await Geolocator.openLocationSettings();
                          await _check();
                        },
                  icon: const Icon(Icons.settings_suggest_rounded),
                  label: const Text(
                    'Open App Settings',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _check,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('I Have Enabled It — Check Again'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepRow({required String number, required String title}) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: context.appColors.primary,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

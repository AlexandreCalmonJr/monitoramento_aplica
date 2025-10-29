// File: lib/services/service_locator.dart
import 'package:agent_windows/services/auth_service.dart';
import 'package:agent_windows/services/background_service.dart';
import 'package:agent_windows/services/module_structure_service.dart';
import 'package:agent_windows/services/monitoring_service.dart';
import 'package:agent_windows/services/settings_service.dart';
import 'package:agent_windows/utils/app_logger.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

final locator = GetIt.instance;

void setupLocator() {
  // Logger
  locator.registerSingleton<Logger>(AppLogger.logger);

  // Serviços
  locator.registerLazySingleton(() => AuthService());
  locator.registerLazySingleton(() => SettingsService(locator<Logger>()));
  locator.registerLazySingleton(() => ModuleStructureService(locator<Logger>(), locator<AuthService>(), authService: locator<AuthService>()));
  locator.registerLazySingleton(() => MonitoringService(locator<Logger>(), locator<AuthService>(), locator<ModuleStructureService>()));
  locator.registerLazySingleton(() => BackgroundService(locator<Logger>(), locator<SettingsService>(), locator<MonitoringService>()));
}
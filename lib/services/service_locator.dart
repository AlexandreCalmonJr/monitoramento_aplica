// File: lib/services/service_locator.dart
import 'package:agent_windows/services/auth_service.dart';
import 'package:agent_windows/services/background_service.dart';
import 'package:agent_windows/services/command_executor_service.dart'; // ✅ Import Necessário
import 'package:agent_windows/services/local_cache_service.dart';
import 'package:agent_windows/services/module_detection_service.dart';
import 'package:agent_windows/services/module_structure_service.dart';
import 'package:agent_windows/services/monitoring_service.dart';
import 'package:agent_windows/services/settings_service.dart';
import 'package:agent_windows/services/websocket_service.dart';
import 'package:agent_windows/utils/app_logger.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';

final locator = GetIt.instance;

void setupLocator() {
  // Logger
  locator.registerSingleton<Logger>(AppLogger.logger);

  // Serviços Básicos
  locator.registerLazySingleton(() => AuthService(
    locator<Logger>(),
    locator<SettingsService>(),
  ));
  locator.registerLazySingleton(() => SettingsService(locator<Logger>()));
  locator.registerLazySingleton(() => LocalCacheService(locator<Logger>()));

  // Serviços de Lógica
  locator.registerLazySingleton(() => ModuleStructureService(
        locator<Logger>(),
        locator<AuthService>(),
      ));

  locator.registerLazySingleton(() => ModuleDetectionService(
        locator<Logger>(),
        locator<AuthService>(),
      ));

  // ✅ CORREÇÃO: Registrando o CommandExecutorService que estava faltando
  locator.registerLazySingleton(() => CommandExecutorService(
        locator<Logger>(),
        locator<AuthService>(),
        locator<SettingsService>(),
      ));

  // Serviço de Monitoramento
  locator.registerLazySingleton(() => MonitoringService(
        locator<Logger>(),
        locator<AuthService>(),
        locator<ModuleStructureService>(),
        locator<LocalCacheService>(),
        locator<SettingsService>(),
      ));

  // Background Service (Depende de todos os acima)
  locator.registerLazySingleton(() => BackgroundService(locator<Logger>(),
      locator<SettingsService>(), locator<MonitoringService>()));

  // WebSocket Service
  locator.registerLazySingleton(() => WebSocketService(locator<Logger>()));
}

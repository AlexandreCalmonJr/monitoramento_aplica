// File: lib/services/service_locator.dart
import 'package:agent_windows/services/auth_service.dart';
import 'package:agent_windows/services/background_service.dart';
import 'package:agent_windows/services/local_cache_service.dart';
// --- INÍCIO DA ADIÇÃO (IMPORT QUE FALTAVA) ---
import 'package:agent_windows/services/module_detection_service.dart';
import 'package:agent_windows/services/module_structure_service.dart';
import 'package:agent_windows/services/monitoring_service.dart';
import 'package:agent_windows/services/settings_service.dart';
import 'package:agent_windows/utils/app_logger.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart';
// --- FIM DA ADIÇÃO ---

final locator = GetIt.instance;

void setupLocator() {
  // Logger
  locator.registerSingleton<Logger>(AppLogger.logger);

  // Serviços
  locator.registerLazySingleton(() => AuthService());
  locator.registerLazySingleton(() => SettingsService(locator<Logger>()));
  
  locator.registerLazySingleton(() => LocalCacheService(locator<Logger>()));

  // CORREÇÃO (Item 21): Remover parâmetros duplicados
  locator.registerLazySingleton(() => ModuleStructureService(
        locator<Logger>(),
        locator<AuthService>(),
      ));
  
  // --- INÍCIO DA ADIÇÃO (SERVIÇO QUE FALTAVA) ---
  // Registra o serviço de detecção para que a StatusScreen possa usá-lo
  locator.registerLazySingleton<ModuleDetectionService>(() => ModuleDetectionService(
        locator<Logger>(),
        locator<AuthService>(),
  ));
  // --- FIM DA ADIÇÃO ---

  locator.registerLazySingleton(() => MonitoringService(
        locator<Logger>(),
        locator<AuthService>(),
        locator<ModuleStructureService>(),
        locator<LocalCacheService>(),
        locator<SettingsService>(),
      ));
      
  locator.registerLazySingleton(() => BackgroundService(locator<Logger>(), locator<SettingsService>(), locator<MonitoringService>()));
}
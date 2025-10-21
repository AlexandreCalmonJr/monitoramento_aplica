// File: lib/services/background_service.dart
import 'dart:async';
import 'dart:ui';

import 'package:agent_windows/services/monitoring_service.dart';
import 'package:agent_windows/services/settings_service.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      isForegroundMode: false,
      autoStart: true,
    ),
    iosConfiguration: IosConfiguration(
      onForeground: onStart,
      onBackground: (service) => true,
      autoStart: true,
    ),
  );
  
  service.startService();
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  final monitoringService = MonitoringService();
  final settingsService = SettingsService();
  Timer? timer;

  Future<void> runCycle(Map<String, dynamic> settings) async {
    final moduleId = settings['moduleId'] as String?;
    final serverUrl = settings['serverUrl'] as String?;
    final sector = settings['sector'] as String?;
    final floor = settings['floor'] as String?;

    if (moduleId != null && serverUrl != null && serverUrl.isNotEmpty) {
      print('Background Service: Coletando dados para o módulo $moduleId');
      await monitoringService.collectAndSendData(
        moduleId: moduleId,
        serverUrl: serverUrl,
        manualSector: sector,
        manualFloor: floor,
      );
    } else {
      print('Background Service: Configurações incompletas. Parando ciclo.');
    }
  }

  service.on('updateSettings').listen((event) async {
    timer?.cancel();
    
    final settings = event!;
    final interval = settings['interval'] as int? ?? 300;

    print('Background Service: Configurações atualizadas. Intervalo: ${interval}s');

    await runCycle(settings);

    timer = Timer.periodic(Duration(seconds: interval), (timer) async {
      await runCycle(settings);
    });
  });

  await settingsService.loadSettings();
  final initialSettings = {
    'moduleId': settingsService.moduleId,
    'serverUrl': 'http://${settingsService.ip}:${settingsService.port}',
    'interval': settingsService.interval,
    'sector': settingsService.sector,
    'floor': settingsService.floor,
  };
  service.invoke('updateSettings', initialSettings);

  print('Background Service: Serviço iniciado.');
}
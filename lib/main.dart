import 'dart:async';
import 'dart:io';

import 'package:agent_windows/providers/agent_provider.dart';
import 'package:agent_windows/services/background_service.dart';
import 'package:agent_windows/services/service_locator.dart';
import 'package:agent_windows/services/system_tray_service.dart';
import 'package:agent_windows/utils/app_logger.dart';
import 'package:agent_windows/utils/window_listener.dart';
import 'package:agent_windows/widgets/home_screen_router.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Inicializar Logger
  await AppLogger.initialize();
  final logger = AppLogger.logger;

  // 2. Configurar Service Locator
  try {
    setupLocator();
    logger.i('Service Locator configurado');
  } catch (e) {
    logger.e('Erro ao configurar Service Locator: $e');
  }

  // 3. Configuração para o gerenciador de janela
  await windowManager.ensureInitialized();

  // 1. Impede que o aplicativo feche ao clicar no 'X'
  await windowManager.setPreventClose(true);

  // 2. Cria e registra nosso "ouvinte" de eventos da janela
  WindowListener listener = MyWindowListener(logger);

  windowManager.addListener(listener);

  // 4. Inicia o serviço de background
  try {
    await locator<BackgroundService>().initialize();
    logger.i('Background Service inicializado');
  } catch (e) {
    logger.e('Erro ao inicializar Background Service: $e');
  }

  // 5. Configuração da bandeja do sistema (System Tray)
  bool trayInitialized = false;
  if (Platform.isWindows) {
    trayInitialized = await initSystemTray();
  }

  // 6. Rodar o App com o Provider
  runApp(
    ChangeNotifierProvider(
      create: (context) => AgentProvider(),
      child: const AgentApp(),
    ),
  );

  // 7. Esconde a janela principal após a inicialização
  if (Platform.isWindows) {
    const WindowOptions windowOptions = WindowOptions(
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (trayInitialized) {
        await windowManager.hide();
      } else {
        logger.w('Bandeja do sistema falhou, mostrando janela principal');
        await windowManager.show();
      }
    });
  }
}

class AgentApp extends StatelessWidget {
  const AgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agente de Monitoramento',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
          surface: const Color(0xFF0F172A),
          background: const Color(0xFF0F172A),
        ),
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      home: const HomeScreenRouter(),
    );
  }
}

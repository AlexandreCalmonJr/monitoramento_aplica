// File: lib/main.dart
import 'dart:async';
import 'dart:io';

import 'package:agent_windows/providers/agent_provider.dart';
// PLACEHOLDER: Estes arquivos serão criados no Passo 3
// Nós os definimos aqui para o 'HomeScreenRouter' funcionar
import 'package:agent_windows/screens/onboarding_screen.dart';
import 'package:agent_windows/screens/status_screen.dart';
import 'package:agent_windows/services/background_service.dart';
import 'package:agent_windows/services/service_locator.dart';
import 'package:agent_windows/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:system_tray/system_tray.dart';
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
  
  // 4. Inicia o serviço de background
  // Nós obtemos a instância do locator
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

Future<bool> initSystemTray() async {
  final SystemTray systemTray = SystemTray();
  String iconPath = '';
  final logger = locator<Logger>(); // Obtém logger do locator

  try {
    if (kDebugMode) {
      iconPath = 'assets/app_icon.ico';
      logger.d('Modo Debug: Usando path do ícone: $iconPath');
    } else {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      iconPath = '$exeDir/data/flutter_assets/assets/app_icon.ico';
      logger.d('Modo Release: Usando path do ícone: $iconPath');
    }
    
    final iconFile = File(iconPath);
    if (!await iconFile.exists()) {
      logger.e('Ícone não encontrado em $iconPath');
      return false;
    }

    await systemTray.initSystemTray(
      title: "Agente de Monitoramento",
      iconPath: iconPath,
    );

    // === NOVO MENU (Sugestão UX 3) ===
    final Menu menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: 'Abrir Painel', 
        onClicked: (menuItem) => windowManager.show()
      ),
      MenuItemLabel(
        label: 'Forçar Sincronização',
        onClicked: (menuItem) async {
          logger.i('Sincronização forçada pelo usuário');
          // TODO: Implementar notificação na bandeja (displayMessage não existe no system_tray)
          // systemTray.displayMessage(
          //   "Agente de Monitoramento",
          //   "Iniciando sincronização forçada...",
          // );
          await locator<BackgroundService>().runCycle();
          // systemTray.displayMessage(
          //   "Agente de Monitoramento",
          //   "Sincronização concluída.",
          // );
        }
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Fechar Agente', 
        onClicked: (menuItem) {
          locator<BackgroundService>().stop();
          exit(0);
        }
      ),
    ]);
    // ===================================

    await systemTray.setContextMenu(menu);

    systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        windowManager.show();
      } else if (eventName == kSystemTrayEventRightClick) {
        systemTray.popUpContextMenu();
      }
    });

    logger.i("Bandeja do sistema inicializada com sucesso.");
    return true;

  } catch (e) {
    logger.e('Erro ao inicializar bandeja do sistema: $e');
    return false;
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
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF1A202C),
        cardColor: const Color(0xFF2D3748),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
          primary: Colors.blue,
          secondary: const Color(0xFF4A5568),
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF2D3748),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
            borderSide: const BorderSide(color: Colors.blue, width: 2),
          ),
          labelStyle: TextStyle(color: Colors.grey[400]),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            fontWeight: FontWeight.bold, 
            color: Colors.white
          ),
          bodyMedium: TextStyle(color: Colors.white70),
        ),
      ),
      // HomeScreen agora será o nosso "Roteador"
      home: const HomeScreenRouter(),
    );
  }
}

// NOVO WIDGET: Roteia para Onboarding ou Painel de Status
class HomeScreenRouter extends StatelessWidget {
  const HomeScreenRouter({super.key});

  @override
  Widget build(BuildContext context) {
    // Assiste ao status do provider
    final status = context.watch<AgentProvider>().status;

    // Use um AnimatedSwitcher para uma transição suave
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: switch (status) {
        // As telas reais serão criadas no Passo 3
        AgentStatus.configured => const StatusScreen(), 
        AgentStatus.unconfigured || AgentStatus.configuring => const OnboardingScreen(),
        // Estado de carregamento inicial
        _ => const Scaffold(
            backgroundColor: Color(0xFF1A202C),
            body: Center(child: CircularProgressIndicator()),
           ),
      },
    );
  }
}
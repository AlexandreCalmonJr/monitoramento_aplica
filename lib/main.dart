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
  final logger = locator<Logger>();

  try {
    if (kDebugMode) {
      // Debug: usa o path relativo do projeto
      iconPath = 'assets/app_icon.ico';
      logger.d('Modo Debug: Usando path do ícone: $iconPath');
    } else {
      // Release: CORRIGIDO - múltiplas tentativas de localização
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      
      // Tenta vários caminhos possíveis
      final possiblePaths = [
        '$exeDir/data/flutter_assets/assets/app_icon.ico',
        '$exeDir/assets/app_icon.ico',
        '$exeDir/app_icon.ico',
      ];
      
      for (final path in possiblePaths) {
        if (await File(path).exists()) {
          iconPath = path;
          logger.d('Ícone encontrado em: $iconPath');
          break;
        }
      }
      
      if (iconPath.isEmpty) {
        logger.e('Ícone não encontrado em nenhum dos caminhos testados');
        return false;
      }
    }
    
    await systemTray.initSystemTray(
      title: "Agente de Monitoramento",
      iconPath: iconPath,
      toolTip: "Agente de Monitoramento - Clique para abrir", // ADICIONADO
    );

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
          await locator<BackgroundService>().runCycle();
        }
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Sair', // RENOMEADO de "Fechar Agente"
        onClicked: (menuItem) async {
          locator<BackgroundService>().stop();
          await windowManager.destroy(); // MELHOR que exit(0)
        }
      ),
      MenuItemLabel(
        label: 'Reiniciar',
        onClicked: (menuItem) async {
          logger.i('Reiniciando o serviço');
          await locator<BackgroundService>().initialize();
        }
      ),
    ]);

    await systemTray.setContextMenu(menu);

    systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        windowManager.show();
        windowManager.focus(); // ADICIONADO - traz janela para frente
      } else if (eventName == kSystemTrayEventRightClick) {
        systemTray.popUpContextMenu();
      }
    });

    logger.i("Bandeja do sistema inicializada com sucesso.");
    return true;

  } catch (e, stackTrace) {
    logger.e('Erro ao inicializar bandeja do sistema: $e', stackTrace: stackTrace);
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
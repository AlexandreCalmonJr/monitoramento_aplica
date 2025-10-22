// File: lib/main.dart
import 'dart:async';
import 'dart:io';

import 'package:agent_windows/background_service.dart';
import 'package:agent_windows/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configuração para o gerenciador de janela
  await windowManager.ensureInitialized();
  
  // Inicia o serviço de background (Windows Timer)
  await BackgroundService().initialize();

  // Configuração da bandeja do sistema (System Tray)
  if (Platform.isWindows) {
    await initSystemTray();
  }

  runApp(const AgentApp());

  // Esconde a janela principal após a inicialização
  if (Platform.isWindows) {
    const WindowOptions windowOptions = WindowOptions(
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.hide(); // Começa escondido
    });
  }
}

Future<void> initSystemTray() async {
  final SystemTray systemTray = SystemTray();

  try {
    // Tenta usar o ícone do app, se não existir usa vazio
    String iconPath = '';
    if (Platform.isWindows) {
      final iconFile = File('data/flutter_assets/assets/app_icon.ico');
      if (await iconFile.exists()) {
        iconPath = iconFile.path;
      }
    }

    // Só inicializa se tiver um ícone válido
    if (iconPath.isEmpty) {
      debugPrint('Aviso: Ícone não encontrado, bandeja do sistema desabilitada');
      debugPrint('Crie um arquivo assets/app_icon.ico para habilitar a bandeja');
      return;
    }

    await systemTray.initSystemTray(
      title: "Agente de Monitoramento",
      iconPath: iconPath,
    );

    final Menu menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
        label: 'Abrir Agente', 
        onClicked: (menuItem) => windowManager.show()
      ),
      MenuItemLabel(
        label: 'Fechar', 
        onClicked: (menuItem) {
          BackgroundService().stop();
          exit(0);
        }
      ),
      MenuItemLabel(
        label: 'Reiniciar Serviço',
        onClicked: (menuItem) {
          BackgroundService().initialize();
        }
      ),
      MenuItemLabel(
        label: 'Fechar', 
        onClicked: (menuItem) {
          BackgroundService().stop();
          exit(0);
        }
      ),
      MenuItemLabel(
        label: 'Reiniciar Serviço',
        onClicked: (menuItem) {
          BackgroundService().initialize();
        }
      ),
    ]);

    await systemTray.setContextMenu(menu);

    systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        windowManager.show();
      } else if (eventName == kSystemTrayEventRightClick) {
        systemTray.popUpContextMenu();
      }
    });
  } catch (e) {
    debugPrint('Erro ao inicializar bandeja do sistema: $e');
    // Continua sem a bandeja do sistema se houver erro
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
      home: const HomeScreen(),
    );
  }
}
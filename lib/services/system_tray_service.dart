import 'dart:io';
import 'package:agent_windows/services/service_locator.dart';
import 'package:agent_windows/services/background_service.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

Future<bool> initSystemTray() async {
  final SystemTray systemTray = SystemTray();
  String iconPath = '';
  final logger = locator<Logger>();

  try {
    if (kDebugMode) {
      iconPath = 'assets/app_icon.ico';
      logger.d('Modo Debug: Usando path do ícone: $iconPath');
    } else {
      final exeDir = File(Platform.resolvedExecutable).parent.path;

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
      toolTip: "Agente de Monitoramento - Clique para abrir",
    );

    final Menu menu = Menu();
    await menu.buildFrom([
      MenuItemLabel(
          label: 'Abrir Painel', onClicked: (menuItem) => windowManager.show()),
      MenuItemLabel(
          label: 'Forçar Sincronização',
          onClicked: (menuItem) async {
            logger.i('Sincronização forçada pelo usuário');
            await locator<BackgroundService>().runCycle();
          }),
      MenuSeparator(),
      MenuItemLabel(
          label: 'Sair',
          onClicked: (menuItem) async {
            locator<BackgroundService>().stop();
            await windowManager.destroy();
          }),
      MenuItemLabel(
          label: 'Reiniciar',
          onClicked: (menuItem) async {
            logger.i('Reiniciando o serviço');
            await locator<BackgroundService>().initialize();
          }),
    ]);

    await systemTray.setContextMenu(menu);

    systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        windowManager.show();
        windowManager.focus();
      } else if (eventName == kSystemTrayEventRightClick) {
        systemTray.popUpContextMenu();
      }
    });

    logger.i("Bandeja do sistema inicializada com sucesso.");
    return true;
  } catch (e, stackTrace) {
    logger.e('Erro ao inicializar bandeja do sistema: $e',
        stackTrace: stackTrace);
    return false;
  }
}

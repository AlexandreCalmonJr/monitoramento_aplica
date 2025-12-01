import 'package:logger/logger.dart';
import 'package:window_manager/window_manager.dart';

class MyWindowListener extends WindowListener {
  final Logger logger;
  MyWindowListener(this.logger);

  @override
  void onWindowClose() async {
    await windowManager.hide();
  }

  @override
  void onWindowMinimize() async {
    await windowManager.hide();
  }

  @override
  void onWindowFocus() {
    logger.d('Janela focada');
  }

  @override
  void onWindowRestore() {
    logger.d('Janela restaurada');
  }

  @override
  void onWindowMaximize() {
    logger.d('Janela maximizada');
  }
}

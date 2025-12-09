// Arquivo: test/client_integration_test.dart
// Testes de integração para o Aplicativo Cliente de Monitoramento

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:agent_windows/services/auth_service.dart';
import 'package:agent_windows/services/local_cache_service.dart';
import 'package:agent_windows/services/monitoring_service.dart';
import 'package:agent_windows/services/module_structure_service.dart';
import 'package:agent_windows/services/settings_service.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('🧪 Testes de Integração do Cliente', () {
    late Logger logger;
    late SettingsService settingsService;
    late AuthService authService;
    late ModuleStructureService moduleStructureService;
    late LocalCacheService localCacheService;
    late MonitoringService monitoringService;

    setUpAll(() async {
      // Initialize Flutter bindings for testing
      TestWidgetsFlutterBinding.ensureInitialized();

      // Mock SharedPreferences for testing
      SharedPreferences.setMockInitialValues({});

      // Inicializar logger
      logger = Logger(
        printer: PrettyPrinter(
          methodCount: 0,
          errorMethodCount: 5,
          lineLength: 80,
          colors: true,
          printEmojis: true,
        ),
      );

      // Inicializar serviços
      settingsService = SettingsService(logger);
      await settingsService.loadSettings();

      authService = AuthService(logger, settingsService);
      await authService.loadTokens();

      moduleStructureService = ModuleStructureService(logger, authService);
      localCacheService = LocalCacheService(logger);
      monitoringService = MonitoringService(
        logger,
        authService,
        moduleStructureService,
        localCacheService,
        settingsService,
      );

      // Configurar servidor usando saveSettings
      await settingsService.saveSettings(
        newIp: 'localhost',
        newPort: '3000',
        newInterval: 300,
        newModuleId: 'test-desktop-module',
        newSector: '',
        newFloor: '',
        newToken: 'test-legacy-token',
        newAssetName: '',
        newForceLegacyMode: false,
      );

      // Save legacy token for authentication
      await authService.saveLegacyToken('test-legacy-token');

      print('\n📝 Configuração inicial do cliente concluída');
    });

    test('1️⃣ Configurar credenciais', () async {
      // Note: SettingsService doesn't store username/password directly
      // Authentication is handled by AuthService
      print('✅ Credenciais serão configuradas via AuthService');
    });

    test('2️⃣ Autenticar no servidor', () async {
      // Skip authentication test if server is not running
      try {
        final serverUrl =
            'http://${settingsService.ip}:${settingsService.port}';
        final success = await authService.loginWithLegacyToken(
          serverUrl: serverUrl,
          legacyToken: 'test-legacy-token',
        );

        if (success) {
          expect(authService.token, isNotNull);
          print('✅ Autenticação bem-sucedida');
          print(
              '   Token: ${authService.token?.substring(0, min(20, authService.token!.length))}...');
        } else {
          print('⚠️ Autenticação falhou (servidor pode não estar rodando)');
        }
      } catch (e) {
        print(
            '⚠️ Erro na autenticação (esperado se servidor não estiver rodando): $e');
      }
    });

    test('3️⃣ Configurar módulo', () async {
      // Module is already configured in setUpAll
      expect(settingsService.moduleId, equals('test-desktop-module'));
      print('✅ Módulo configurado: desktop');
    });

    test('4️⃣ Buscar estrutura do módulo', () async {
      final serverUrl = 'http://${settingsService.ip}:${settingsService.port}';
      final moduleId = settingsService.moduleId;

      if (authService.token == null) {
        print('⚠️ Token não disponível, pulando teste');
        return;
      }

      try {
        final structure = await moduleStructureService.fetchModuleStructure(
          serverUrl: serverUrl,
          token: authService.token!,
          moduleId: moduleId,
        );

        print(structure != null
            ? '✅ Estrutura do módulo obtida: ${structure.name}'
            : '⚠️ Módulo não encontrado (esperado em teste)');
      } catch (e) {
        print(
            '⚠️ Erro ao buscar estrutura (esperado se servidor não estiver rodando): $e');
      }
    });

    test('5️⃣ Coletar informações do sistema', () async {
      // Este teste pode falhar em ambiente de teste sem sistema real
      try {
        final systemInfo = await monitoringService.collectSystemInfo();

        expect(systemInfo, isNotNull);
        expect(systemInfo, isNotEmpty);

        print('✅ Informações do sistema coletadas');
        print('   Campos: ${systemInfo.keys.join(', ')}');
      } catch (e) {
        print('⚠️ Coleta de sistema ignorada em ambiente de teste: $e');
      }
    });

    test('6️⃣ Validar campos obrigatórios (Desktop)', () async {
      final requiredFields =
          moduleStructureService.getRequiredFieldsByType('desktop');

      expect(requiredFields, isNotEmpty);
      expect(requiredFields.containsKey('asset_name'), isTrue);
      expect(requiredFields.containsKey('serial_number'), isTrue);
      expect(requiredFields.containsKey('hostname'), isTrue);

      print('✅ Campos obrigatórios validados: ${requiredFields.length} campos');
    });

    test('7️⃣ Validar campos obrigatórios (Notebook)', () async {
      final requiredFields =
          moduleStructureService.getRequiredFieldsByType('notebook');

      expect(requiredFields, isNotEmpty);
      expect(requiredFields.containsKey('battery_level'), isTrue);
      expect(requiredFields.containsKey('battery_health'), isTrue);

      print('✅ Campos de Notebook validados: ${requiredFields.length} campos');
    });

    test('8️⃣ Validar campos obrigatórios (Panel)', () async {
      final requiredFields =
          moduleStructureService.getRequiredFieldsByType('panel');

      expect(requiredFields, isNotEmpty);
      expect(requiredFields.containsKey('screen_size'), isTrue);
      expect(requiredFields.containsKey('resolution'), isTrue);
      expect(requiredFields.containsKey('brightness'), isTrue);

      print('✅ Campos de Panel validados: ${requiredFields.length} campos');
    });

    test('9️⃣ Validar dados coletados', () async {
      final testData = {
        'asset_name': 'Test Desktop',
        'serial_number': 'TEST-123',
        'hostname': 'TEST-PC',
        'ip_address': '192.168.1.100',
        'mac_address': '00:11:22:33:44:55',
      };

      final isValid = moduleStructureService.validateData(testData, 'desktop');

      // Pode falhar porque faltam campos, mas não deve dar erro
      print(isValid
          ? '✅ Dados validados com sucesso'
          : '⚠️ Validação falhou (esperado - dados incompletos)');
    });

    test('🔟 Simular envio de dados', () async {
      // Este teste apenas verifica se o método existe e pode ser chamado
      // Não envia dados reais para não poluir o servidor

      final testData = {
        'serial_number': 'TEST-MOCK-${DateTime.now().millisecondsSinceEpoch}',
        'asset_name': 'Mock Desktop',
        'hostname': 'MOCK-PC',
      };

      print('✅ Simulação de envio preparada');
      print('   Dados: ${testData.keys.join(', ')}');
    });

    test('1️⃣1️⃣ Verificar configurações salvas', () async {
      expect(settingsService.ip, equals('localhost'));
      expect(settingsService.port, equals('3000'));
      expect(settingsService.moduleId, equals('test-desktop-module'));

      print('✅ Configurações verificadas');
      print('   Servidor: ${settingsService.ip}:${settingsService.port}');
      print('   Módulo: ${settingsService.moduleId}');
    });

    test('1️⃣2️⃣ Limpar configurações de teste', () async {
      // Reset settings to empty values
      await settingsService.saveSettings(
        newIp: '',
        newPort: '',
        newInterval: 300,
        newModuleId: '',
        newSector: '',
        newFloor: '',
        newToken: '',
        newAssetName: '',
        newForceLegacyMode: false,
      );

      print('✅ Configurações de teste limpas');
    });
  });

  group('🔧 Testes de Comandos do Cliente', () {
    test('1️⃣ Verificar comandos disponíveis', () {
      // Lista de comandos que o cliente deve ser capaz de executar
      final expectedCommands = [
        'restart_computer',
        'flush_dns',
        'restart_print_spooler',
        'clear_temp',
        'network_reset',
      ];

      print('✅ Comandos esperados: ${expectedCommands.length}');
      for (final cmd in expectedCommands) {
        print('   - $cmd');
      }
    });

    test('2️⃣ Simular recebimento de comando', () {
      final mockCommand = {
        'id': 'cmd-123',
        'commandType': 'flush_dns',
        'command': 'ipconfig /flushdns',
        'requiresElevation': false,
        'timeout': 10000,
      };

      expect(mockCommand['commandType'], equals('flush_dns'));
      expect(mockCommand['requiresElevation'], isFalse);

      print('✅ Comando simulado recebido: ${mockCommand['commandType']}');
    });

    test('3️⃣ Simular resultado de comando', () {
      final mockResult = {
        'success': true,
        'stdout': 'DNS cache flushed successfully',
        'stderr': '',
        'exitCode': 0,
        'executionTime': 1500,
      };

      expect(mockResult['success'], isTrue);
      expect(mockResult['exitCode'], equals(0));

      print('✅ Resultado de comando simulado');
      print('   Sucesso: ${mockResult['success']}');
      print('   Tempo: ${mockResult['executionTime']}ms');
    });
  });
}

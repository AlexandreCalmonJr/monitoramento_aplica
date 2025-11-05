// File: lib/screens/onboarding_screen.dart
import 'package:agent_windows/providers/agent_provider.dart';
import 'package:agent_windows/widgets/module_list_item.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AgentProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 600,
          child: Column(
            children: [
              // Cabeçalho
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.shield_outlined, 
                        color: theme.colorScheme.primary, 
                        size: 32
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Configurar Agente',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Siga os passos para ativar o monitoramento',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Conteúdo da Página
              Expanded(
                child: PageView(
                  controller: provider.pageController,
                  // Desativa o scroll manual
                  physics: const NeverScrollableScrollPhysics(),
                  children: const [
                    _OnboardingStep1(),
                    _OnboardingStep2(),
                    _OnboardingStep3(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- PÁGINA 1: CONEXÃO ---
class _OnboardingStep1 extends StatelessWidget {
  const _OnboardingStep1();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AgentProvider>();
    final isLoading = provider.moduleFetchStatus == ModuleFetchStatus.loading;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            icon: Icons.dns_outlined,
            title: 'Passo 1: Conexão com Servidor',
            subtitle: 'Endereço e credenciais de acesso',
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: provider.ipController,
                  decoration: const InputDecoration(
                    labelText: 'Endereço IP',
                    prefixIcon: Icon(Icons.router_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: provider.portController,
                  decoration: const InputDecoration(
                    labelText: 'Porta',
                    prefixIcon: Icon(Icons.settings_ethernet),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: provider.tokenController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Token de Autenticação',
              prefixIcon: Icon(Icons.key_outlined),
              helperText: 'Token fornecido pelo administrador',
            ),
          ),
          const SizedBox(height: 24),

          // Exibição de Erro
          if (provider.moduleFetchStatus == ModuleFetchStatus.error)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.5)),
              ),
              child: Text(
                'Erro: ${provider.errorMessage}',
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: isLoading 
              ? null 
              : () => context.read<AgentProvider>().fetchModules(),
            icon: isLoading 
              ? Container(
                  width: 20, 
                  height: 20, 
                  margin: const EdgeInsets.only(right: 8),
                  child: const CircularProgressIndicator(strokeWidth: 2)
                ) 
              : const Icon(Icons.arrow_forward),
            label: Text(isLoading ? 'Testando...' : 'Testar e Continuar'),
          ),
          
          if (provider.status == AgentStatus.configuring)
            TextButton(
              onPressed: () => context.read<AgentProvider>().cancelReconfiguration(),
              child: const Text('Cancelar Reconfiguração'),
            ),
        ],
      ),
    );
  }
}

// --- PÁGINA 2: SELEÇÃO DE MÓDULO ---
class _OnboardingStep2 extends StatelessWidget {
  const _OnboardingStep2();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AgentProvider>();
    final modules = provider.filteredModules; // MUDANÇA AQUI

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              _buildSectionHeader(
                icon: Icons.extension_outlined,
                title: 'Passo 2: Seleção do Módulo',
                subtitle: 'Selecione o tipo de ativo que esta máquina representa',
              ),
              
              // NOVO: Campo de busca
              const SizedBox(height: 16),
              TextField(
                onChanged: (value) => provider.updateSearchQuery(value),
                decoration: InputDecoration(
                  labelText: 'Buscar módulo',
                  hintText: 'Digite o nome ou tipo do módulo',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: provider.searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => provider.clearSearch(),
                        )
                      : null,
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // MELHORADO: Mensagem quando não há resultados
        Expanded(
          child: modules.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        provider.searchQuery.isEmpty 
                            ? Icons.inbox_outlined 
                            : Icons.search_off,
                        size: 64,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        provider.searchQuery.isEmpty
                            ? 'Nenhum módulo encontrado no servidor.'
                            : 'Nenhum módulo corresponde à busca.',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                      if (provider.searchQuery.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => provider.clearSearch(),
                          icon: const Icon(Icons.clear),
                          label: const Text('Limpar busca'),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  itemCount: modules.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final module = modules[index];
                    return ModuleListItem(
                      module: module,
                      isSelected: provider.selectedModuleId == module.id,
                      onTap: () => provider.setSelectedModule(module.id),
                    );
                  },
                ),
        ),
        
        // Contador de resultados (NOVO)
        if (modules.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
            child: Text(
              provider.searchQuery.isEmpty
                  ? '${modules.length} módulos disponíveis'
                  : '${modules.length} resultado(s) encontrado(s)',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        
        // Navegação
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            children: [
              TextButton(
                onPressed: () {
                  provider.clearSearch(); // ADICIONADO
                  provider.previousOnboardingPage();
                },
                child: const Text('Voltar'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: provider.selectedModuleId == null 
                  ? null
                  : () => provider.nextOnboardingPage(),
                child: const Text('Continuar'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- PÁGINA 3: CONFIGURAÇÃO FINAL ---
class _OnboardingStep3 extends StatelessWidget {
  const _OnboardingStep3();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AgentProvider>();
    final selectedModule = provider.selectedModule;

    if (selectedModule == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Erro: Módulo não selecionado'),
            TextButton(
              onPressed: () => provider.previousOnboardingPage(),
              child: const Text('Voltar'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            icon: Icons.settings_outlined,
            title: 'Passo 3: Configuração Final',
            subtitle: 'Você está conectando o módulo: ${selectedModule.name}',
          ),
          const SizedBox(height: 24),

          // Identificação Manual
          _buildSectionHeader(
            icon: Icons.location_on_outlined,
            title: 'Identificação Manual',
            subtitle: 'Opcional: Localização física do dispositivo',
            isSubheader: true,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: provider.sectorController,
                  decoration: const InputDecoration(
                    labelText: 'Setor',
                    prefixIcon: Icon(Icons.business_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: provider.floorController,
                  decoration: const InputDecoration(
                    labelText: 'Andar',
                    prefixIcon: Icon(Icons.stairs_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Intervalo
          _buildSectionHeader(
            icon: Icons.timer_outlined,
            title: 'Configurações Gerais',
            subtitle: 'Frequência de sincronização',
            isSubheader: true,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: provider.selectedInterval,
            decoration: const InputDecoration(
              labelText: 'Intervalo de Sincronização',
              prefixIcon: Icon(Icons.timer_outlined),
            ),
            items: provider.intervalOptions.map((option) {
              return DropdownMenuItem<int>(
                value: option['value'],
                child: Text(option['label']),
              );
            }).toList(),
            onChanged: (newValue) => provider.setSelectedInterval(newValue),
          ),
          const SizedBox(height: 32),
          
          // Navegação
          Row(
            children: [
              TextButton(
                onPressed: () => provider.previousOnboardingPage(),
                child: const Text('Voltar'),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => provider.saveSettingsAndRestartService(),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar e Ativar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Helper Widget ---
Widget _buildSectionHeader({
  required IconData icon,
  required String title,
  required String subtitle,
  bool isSubheader = false,
}) {
  return Row(
    children: [
      Icon(
        icon, 
        size: isSubheader ? 20 : 24, 
        color: isSubheader ? Colors.grey[400] : Colors.blue
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: isSubheader ? 16 : 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[400],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}
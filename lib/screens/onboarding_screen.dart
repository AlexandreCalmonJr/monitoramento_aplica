// File: lib/screens/onboarding_screen.dart
import 'package:agent_windows/providers/agent_provider.dart';
import 'package:agent_windows/widgets/app_card.dart';
import 'package:agent_windows/widgets/module_list_item.dart';
import 'package:agent_windows/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<AgentProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: SizedBox(
          width: 700,
          child: Column(
            children: [
              // Cabeçalho
              Padding(
                padding: const EdgeInsets.all(32.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.shield_outlined,
                          color: Color(0xFF2563EB), size: 32),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Configurar Agente',
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFFAFAFA),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Siga os passos para ativar o monitoramento',
                            style: const TextStyle(
                              color: Color(0xFFA1A1AA),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(begin: -0.5, end: 0),

              // Conteúdo da Página
              Expanded(
                child: PageView(
                  controller: provider.pageController,
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
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            icon: Icons.dns_outlined,
            title: 'Passo 1: Conexão com Servidor',
            subtitle: 'Endereço e credenciais de acesso',
          ).animate().fadeIn(delay: 200.ms).slideX(),
          
          const SizedBox(height: 32),
          
          AppCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: provider.ipController,
                        style: const TextStyle(color: Colors.white),
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
                        style: const TextStyle(color: Colors.white),
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
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Token de Autenticação',
                    prefixIcon: Icon(Icons.key_outlined),
                    helperText: 'Token fornecido pelo administrador',
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2, end: 0),

          const SizedBox(height: 24),
          
          AppCard(
            padding: EdgeInsets.zero,
            child: CheckboxListTile(
              title: const Text(
                "Forçar Modo Legado (somente Desktop/Totem)",
                style: TextStyle(color: Color(0xFFFAFAFA), fontSize: 14),
              ),
              subtitle: const Text(
                "Ignora a seleção de módulos e envia para /api/monitor. (Não funciona para Notebooks)",
                style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 12),
              ),
              value: provider.forceLegacyMode,
              onChanged: (value) {
                if (value != null) {
                  context.read<AgentProvider>().updateForceLegacyMode(value);
                }
              },
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: const Color(0xFF2563EB),
              checkColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ).animate().fadeIn(delay: 400.ms),

          const SizedBox(height: 24),

          if (provider.moduleFetchStatus == ModuleFetchStatus.error)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFEF4444)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Erro: ${provider.errorMessage}',
                      style: const TextStyle(color: Color(0xFFEF4444)),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(),

          const SizedBox(height: 16),
          
          PrimaryButton(
            onPressed: isLoading
                ? null
                : () => context.read<AgentProvider>().fetchModules(),
            text: isLoading ? 'Testando Conexão...' : 'Testar e Continuar',
            icon: isLoading ? null : Icons.arrow_forward,
            isLoading: isLoading,
          ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.2, end: 0),

          if (provider.status == AgentStatus.configuring)
            Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: TextButton(
                onPressed: () =>
                    context.read<AgentProvider>().cancelReconfiguration(),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFA1A1AA)),
                child: const Text('Cancelar Reconfiguração'),
              ),
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
    final modules = provider.filteredModules;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            children: [
              _buildSectionHeader(
                icon: Icons.extension_outlined,
                title: 'Passo 2: Seleção do Módulo',
                subtitle:
                    'Selecione o tipo de ativo que esta máquina representa',
              ).animate().fadeIn(delay: 200.ms).slideX(),
              const SizedBox(height: 24),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  onChanged: (value) => provider.updateSearchQuery(value),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Buscar módulo',
                    hintText: 'Digite o nome ou tipo do módulo',
                    prefixIcon: const Icon(Icons.search),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    fillColor: Colors.transparent,
                    suffixIcon: provider.searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => provider.clearSearch(),
                          )
                        : null,
                  ),
                ),
              ).animate().fadeIn(delay: 300.ms),
            ],
          ),
        ),
        const SizedBox(height: 16),
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
                        color: const Color(0xFF27272A),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        provider.searchQuery.isEmpty
                            ? 'Nenhum módulo encontrado no servidor.'
                            : 'Nenhum módulo corresponde à busca.',
                        style: const TextStyle(color: Color(0xFFA1A1AA)),
                      ),
                      if (provider.searchQuery.isNotEmpty) ...[
                        const SizedBox(height: 16),
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
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  itemCount: modules.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final module = modules[index];
                    return ModuleListItem(
                      module: module,
                      isSelected: provider.selectedModuleId == module.id,
                      onTap: () => provider.setSelectedModule(module.id),
                      searchQuery: provider.searchQuery,
                    ).animate().fadeIn(delay: (50 * index).ms).slideX();
                  },
                ),
        ),
        if (modules.isNotEmpty)
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
            child: Text(
              provider.searchQuery.isEmpty
                  ? '${modules.length} módulos disponíveis'
                  : '${modules.length} resultado(s) encontrado(s)',
              style: const TextStyle(
                color: Color(0xFFA1A1AA),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ),

        // Navegação
        Padding(
          padding: const EdgeInsets.all(32.0),
          child: Row(
            children: [
              TextButton(
                onPressed: () {
                  provider.clearSearch();
                  provider.previousOnboardingPage();
                },
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFA1A1AA)),
                child: const Text('Voltar'),
              ),
              const Spacer(),
              PrimaryButton(
                onPressed: provider.selectedModuleId == null
                    ? null
                    : () => provider.nextOnboardingPage(),
                text: 'Continuar',
                icon: Icons.arrow_forward,
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

    final subtitle = provider.forceLegacyMode
        ? 'Enviando dados para o Sistema Legado (Totem)'
        : 'Você está conectando o módulo: ${selectedModule?.name ?? 'N/A'}';

    if (selectedModule == null && !provider.forceLegacyMode) {
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
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(
            icon: Icons.settings_outlined,
            title: 'Passo 3: Configuração Final',
            subtitle: subtitle,
          ).animate().fadeIn(delay: 200.ms).slideX(),
          
          const SizedBox(height: 32),

          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSubheader('Identificação Manual', Icons.label_outline),
                const SizedBox(height: 16),
                TextFormField(
                  controller: provider.assetNameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Nome do Ativo (Opcional)',
                    prefixIcon: Icon(Icons.badge_outlined),
                    helperText: 'Deixe em branco para usar o nome do computador',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: provider.sectorController,
                        style: const TextStyle(color: Colors.white),
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
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Andar',
                          prefixIcon: Icon(Icons.stairs_outlined),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.2, end: 0),
          
          const SizedBox(height: 24),

          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSubheader('Configurações Gerais', Icons.timer_outlined),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: provider.selectedInterval,
                  dropdownColor: const Color(0xFF18181B),
                  style: const TextStyle(color: Colors.white),
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
              ],
            ),
          ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2, end: 0),
          
          const SizedBox(height: 32),

          // Navegação
          Row(
            children: [
              TextButton(
                onPressed: () {
                  if (provider.forceLegacyMode) {
                    provider.pageController.animateToPage(0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut);
                  } else {
                    provider.previousOnboardingPage();
                  }
                },
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFA1A1AA)),
                child: const Text('Voltar'),
              ),
              const Spacer(),
              PrimaryButton(
                onPressed: () => provider.saveSettingsAndRestartService(),
                text: 'Salvar e Ativar',
                icon: Icons.save_outlined,
                backgroundColor: const Color(0xFF10B981),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- Helper Widgets ---
Widget _buildSectionHeader({
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  return Row(
    children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF2563EB).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 24, color: const Color(0xFF2563EB)),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFAFAFA),
              ),
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFFA1A1AA),
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

Widget _buildSubheader(String title, IconData icon) {
  return Row(
    children: [
      Icon(icon, size: 18, color: const Color(0xFFA1A1AA)),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFFE4E4E7),
        ),
      ),
    ],
  );
}

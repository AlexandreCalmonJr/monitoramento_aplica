import 'package:agent_windows/providers/agent_provider.dart';
import 'package:agent_windows/screens/onboarding_screen.dart';
import 'package:agent_windows/screens/status_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class HomeScreenRouter extends StatelessWidget {
  const HomeScreenRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AgentProvider>().status;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: switch (status) {
        AgentStatus.configured => const StatusScreen(),
        AgentStatus.unconfigured ||
        AgentStatus.configuring =>
          const OnboardingScreen(),
        _ => const Scaffold(
            backgroundColor: Color(0xFF0F172A),
            body: Center(child: CircularProgressIndicator()),
          ),
      },
    );
  }
}

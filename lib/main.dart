// Ficheiro: lib/main.dart
// -----------------------
// Ponto de entrada da aplicação Flutter.
// Inicia a interface gráfica e define o tema visual.

import 'package:agent_windows/screens/home_screen.dart';
import 'package:flutter/material.dart';

void main() {
  // Garante que os widgets do Flutter sejam inicializados antes de a app correr.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AgentApp());
}

class AgentApp extends StatelessWidget {
  const AgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Agente de Monitoramento',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Tema escuro, ideal para aplicações que ficam a correr em segundo plano.
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF1A1A2E),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE94560),
          brightness: Brightness.dark,
          primary: const Color(0xFFE94560),
          secondary: const Color(0xFF16213E),
        ),
        useMaterial3: true,
        // Estilo global para os campos de texto.
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          filled: true,
          fillColor: const Color(0xFF16213E),
        ),
        // Estilo global para os botões.
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE94560),
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
      ),
      home: const HomeScreen(),
    );
  }
}


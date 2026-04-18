import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zinemo/config/api_client.dart';
import 'package:zinemo/config/config.dart';
import 'package:zinemo/config/router.dart';
import 'package:zinemo/services/hive_manager.dart';
import 'package:zinemo/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final localEnv = await _loadLocalEnv();
  final supabaseUrl =
      AppConfig.supabaseUrl != 'https://your-project.supabase.co'
      ? AppConfig.supabaseUrl
      : (localEnv['SUPABASE_URL'] ?? '');
  final supabaseAnonKey = AppConfig.supabaseAnonKey != 'your-anon-key'
      ? AppConfig.supabaseAnonKey
      : (localEnv['SUPABASE_ANON_KEY'] ?? '');

  final hasSupabaseConfig =
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  if (!hasSupabaseConfig) {
    runApp(
      const _BootstrapErrorApp(
        title: 'Configuration Required',
        message:
            'SUPABASE_URL and SUPABASE_ANON_KEY are missing.\n\n'
            'Add them to frontend/.env or run with:\n'
            'flutter run --dart-define-from-file=.env',
      ),
    );
    return;
  }

  try {
    // Initialize Supabase with session recovery enabled
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);

    // Initialize API client
    ApiClient.initialize();

    // Initialize Hive local cache
    await HiveManager.initialize();

    runApp(const ProviderScope(child: ZinemoApp()));
  } catch (error) {
    runApp(
      _BootstrapErrorApp(
        title: 'Startup Failed',
        message: 'App initialization failed.\n\n$error',
      ),
    );
  }
}

Future<Map<String, String>> _loadLocalEnv() async {
  try {
    final raw = await rootBundle.loadString('.env');
    return _parseEnv(raw);
  } catch (_) {
    return const {};
  }
}

Map<String, String> _parseEnv(String raw) {
  final values = <String, String>{};

  for (final line in raw.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }

    final separator = trimmed.indexOf('=');
    if (separator <= 0) {
      continue;
    }

    final key = trimmed.substring(0, separator).trim();
    var value = trimmed.substring(separator + 1).trim();

    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }

    values[key] = value;
  }

  return values;
}

class _BootstrapErrorApp extends StatelessWidget {
  final String title;
  final String message;

  const _BootstrapErrorApp({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Zinemo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 56),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ZinemoApp extends StatelessWidget {
  const ZinemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Zinemo',
      theme: AppTheme.darkTheme,
      routerConfig: AppRouter.instance,
      debugShowCheckedModeBanner: false,
    );
  }
}

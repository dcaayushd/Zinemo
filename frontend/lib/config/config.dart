/// Environment configuration for Zinemo app
class AppConfig {
  // Supabase Configuration
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://your-project.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'your-anon-key',
  );

  // API Configuration
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const String mlServiceUrl = String.fromEnvironment(
    'ML_SERVICE_URL',
    defaultValue: 'http://localhost:8000',
  );

  // TMDB Configuration (public access key)
  static const String tmdbApiKey = String.fromEnvironment(
    'TMDB_API_KEY',
    defaultValue: 'your-tmdb-api-key',
  );

  // App Settings
  static const bool isProduction = bool.fromEnvironment(
    'IS_PRODUCTION',
    defaultValue: false,
  );

  static const Duration requestTimeout = Duration(seconds: 10);
  static const int maxRetries = 3;
}

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zinemo/config/config.dart';

/// Configures and manages Dio HTTP client with auth interceptors
class ApiClient {
  static late Dio _dio;
  static bool _initialized = false;
  static const Duration _baseRetryDelay = Duration(milliseconds: 500);
  static const int _maxRetries = AppConfig.maxRetries;

  static String get _baseUrl {
    final normalizedBase = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/$'), '');
    return '$normalizedBase/api';
  }

  static void initialize() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        contentType: 'application/json',
        validateStatus: (status) => status! < 500,
      ),
    );

    // Auth interceptor - add Supabase JWT token
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            final session = Supabase.instance.client.auth.currentSession;
            if (session?.accessToken != null) {
              options.headers['Authorization'] =
                  'Bearer ${session!.accessToken}';
            }
          } catch (e) {
            // Silent failure - continue without auth
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          await _handleRetry(error, handler);
        },
      ),
    );

    // Logging interceptor (dev only)
    _dio.interceptors.add(LoggingInterceptor());
    _initialized = true;
  }

  static void _ensureInitialized() {
    if (!_initialized) {
      initialize();
    }
  }

  @visibleForTesting
  static Dio get dioForTesting {
    _ensureInitialized();
    return _dio;
  }

  @visibleForTesting
  static void setAdapterForTesting(HttpClientAdapter adapter) {
    _ensureInitialized();
    _dio.httpClientAdapter = adapter;
  }

  @visibleForTesting
  static void resetForTesting() {
    _initialized = false;
    initialize();
  }

  static Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    _ensureInitialized();
    try {
      return await _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: options,
      );
    } on DioException {
      rethrow;
    }
  }

  static Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Options? options,
  }) async {
    _ensureInitialized();
    try {
      return await _dio.post<T>(path, data: data, options: options);
    } on DioException {
      rethrow;
    }
  }

  static Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Options? options,
  }) async {
    _ensureInitialized();
    try {
      return await _dio.patch<T>(path, data: data, options: options);
    } on DioException {
      rethrow;
    }
  }

  static Future<Response<T>> delete<T>(String path, {Options? options}) async {
    _ensureInitialized();
    try {
      return await _dio.delete<T>(path, options: options);
    } on DioException {
      rethrow;
    }
  }

  static bool _shouldRetry(DioException error, int retryCount) {
    if (retryCount >= _maxRetries) {
      return false;
    }

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return true;
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode ?? 0;
        return statusCode >= 500;
      default:
        return false;
    }
  }

  static Future<void> _handleRetry(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final requestOptions = error.requestOptions;
    final retryCount = (requestOptions.extra['retry_count'] as int?) ?? 0;

    if (!_shouldRetry(error, retryCount)) {
      handler.next(error);
      return;
    }

    final delay = _baseRetryDelay * (1 << retryCount);

    try {
      await Future.delayed(delay);
      requestOptions.extra['retry_count'] = retryCount + 1;

      final response = await _dio.fetch<dynamic>(requestOptions);
      handler.resolve(response);
    } on DioException catch (retryError) {
      await _handleRetry(retryError, handler);
    } catch (error) {
      handler.next(
        DioException(
          requestOptions: requestOptions,
          error: error,
          type: DioExceptionType.unknown,
        ),
      );
    }
  }
}

/// Logging interceptor for development
class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Silent logging in production
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // Silent logging in production
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Silent logging in production
    super.onError(err, handler);
  }
}

import 'package:hive_flutter/hive_flutter.dart';
import 'package:zinemo/models/content.dart';
import 'package:zinemo/models/log.dart';

/// Manages local Hive database for offline support and caching
class HiveManager {
  static const String contentBoxName = 'content_cache';
  static const String logsBoxName = 'logs';
  static const String userBoxName = 'user_preferences';
  static const String cacheMetaBoxName = 'cache_metadata';

  // Cache TTL: 5 minutes
  static const Duration cacheTTL = Duration(minutes: 5);

  static late Box<dynamic> contentBox;
  static late Box<dynamic> logsBox;
  static late Box<dynamic> userBox;
  static late Box<dynamic> cacheMetaBox;

  /// Initialize Hive and open boxes
  static Future<void> initialize() async {
    await Hive.initFlutter();

    // Register adapters for custom types
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(ContentAdapter());
    }
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(LogAdapter());
    }

    // Open boxes
    contentBox = await Hive.openBox(contentBoxName);
    logsBox = await Hive.openBox(logsBoxName);
    userBox = await Hive.openBox(userBoxName);
    cacheMetaBox = await Hive.openBox(cacheMetaBoxName);
  }

  /// Save content to cache with TTL
  static Future<void> cacheContent(String key, Content content) async {
    await contentBox.put(key, content);
    await cacheMetaBox.put(
      '${key}_timestamp',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Get content from cache if not expired
  static Content? getCachedContent(String key) {
    final timestamp = cacheMetaBox.get('${key}_timestamp') as int?;
    if (timestamp == null) return null;

    final cachedAt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (DateTime.now().difference(cachedAt) > cacheTTL) {
      contentBox.delete(key);
      cacheMetaBox.delete('${key}_timestamp');
      return null;
    }

    return contentBox.get(key) as Content?;
  }

  /// Cache multiple content items
  static Future<void> cacheContentList(String key, List<Content> items) async {
    final Map<String, Content> map = {
      for (var item in items) '${item.tmdbId}_${item.mediaType}': item,
    };
    await contentBox.putAll(map);
    await cacheMetaBox.put(
      '${key}_list_timestamp',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Get cached content list
  static List<Content>? getCachedContentList(String key) {
    final timestamp = cacheMetaBox.get('${key}_list_timestamp') as int?;
    if (timestamp == null) return null;

    final cachedAt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    if (DateTime.now().difference(cachedAt) > cacheTTL) {
      cacheMetaBox.delete('${key}_list_timestamp');
      return null;
    }

    final items = contentBox.values.whereType<Content>().toList();
    return items.isNotEmpty ? items : null;
  }

  /// Save log to local box
  static Future<void> saveLog(Log log) async {
    await logsBox.put(log.id, log);
  }

  /// Get all local logs
  static List<Log> getAllLogs() {
    return logsBox.values.whereType<Log>().toList();
  }

  /// Delete log
  static Future<void> deleteLog(String logId) async {
    await logsBox.delete(logId);
  }

  /// Save user preference
  static Future<void> saveUserPref(String key, dynamic value) async {
    await userBox.put(key, value);
  }

  /// Get user preference
  static dynamic getUserPref(String key) {
    return userBox.get(key);
  }

  /// Clear all caches
  static Future<void> clearCache() async {
    await contentBox.clear();
    await cacheMetaBox.clear();
  }

  /// Clear logs
  static Future<void> clearLogs() async {
    await logsBox.clear();
  }

  /// Close all boxes
  static Future<void> close() async {
    await Hive.close();
  }
}

/// Adapter for Content model
class ContentAdapter extends TypeAdapter<Content> {
  @override
  final typeId = 0;

  @override
  Content read(BinaryReader reader) {
    return Content.fromJson(Map<String, dynamic>.from(reader.readMap()));
  }

  @override
  void write(BinaryWriter writer, Content obj) {
    writer.writeMap(obj.toJson());
  }
}

/// Adapter for Log model
class LogAdapter extends TypeAdapter<Log> {
  @override
  final typeId = 1;

  @override
  Log read(BinaryReader reader) {
    return Log.fromJson(Map<String, dynamic>.from(reader.readMap()));
  }

  @override
  void write(BinaryWriter writer, Log obj) {
    writer.writeMap(obj.toJson());
  }
}

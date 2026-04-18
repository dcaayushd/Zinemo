import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zinemo/config/api_client.dart';
import 'package:zinemo/services/recommendation_service.dart';

class _TestAdapter implements HttpClientAdapter {
  _TestAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }
}

void main() {
  setUp(() {
    ApiClient.resetForTesting();
  });

  test(
    'parses recommendation envelope response for for-you endpoint',
    () async {
      ApiClient.setAdapterForTesting(
        _TestAdapter((options) async {
          expect(options.path, '/recommendations/foryou');
          expect(options.queryParameters['genre'], 'Drama');
          expect(options.queryParameters['limit'], 2);

          return ResponseBody.fromString(
            jsonEncode({
              'recommendations': [
                {
                  'tmdb_id': 101,
                  'media_type': 'movie',
                  'score': 0.91,
                  'reason': 'Because you liked sci-fi dramas',
                  'algorithm': 'hybrid',
                  'title': 'The Sample Movie',
                  'poster_path': '/poster.jpg',
                },
              ],
              'page': 1,
              'mode': 'scratch',
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }),
      );

      final results = await RecommendationService.getForYou(
        genre: 'Drama',
        limit: 2,
      );

      expect(results, hasLength(1));
      expect(results.first.tmdbId, 101);
      expect(results.first.mediaType, 'movie');
      expect(results.first.algorithm, 'hybrid');
      expect(results.first.title, 'The Sample Movie');
      expect(results.first.posterPath, '/poster.jpg');
    },
  );

  test(
    'parses recommendation envelope response for similar endpoint',
    () async {
      ApiClient.setAdapterForTesting(
        _TestAdapter((options) async {
          expect(options.path, '/recommendations/similar/55');

          return ResponseBody.fromString(
            jsonEncode({
              'recommendations': [
                {
                  'tmdb_id': 777,
                  'media_type': 'tv',
                  'score': 0.88,
                  'reason': 'Close semantic match',
                  'algorithm': 'pgvector',
                },
              ],
              'mode': 'hybrid',
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }),
      );

      final results = await RecommendationService.getSimilar(55);

      expect(results, hasLength(1));
      expect(results.first.tmdbId, 777);
      expect(results.first.mediaType, 'tv');
      expect(results.first.algorithm, 'pgvector');
    },
  );
}

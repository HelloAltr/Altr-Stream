import 'package:flutter_test/flutter_test.dart';
import 'package:altr_stream_admin/core/auth/models/altr_api_key.dart';

void main() {
  group('AltrApiKey Expiration and Timezone Parsing Tests', () {
    test('1-hour future expiration in UTC parses accurately and is not expired', () {
      final nowUtc = DateTime.now().toUtc();
      final oneHourLaterUtc = nowUtc.add(const Duration(hours: 1));

      final json = {
        'id': 'test-1-hour-id',
        'name': 'One Hour Key',
        'key_prefix': 'altr_live_test...',
        'scopes': ['read', 'write'],
        'is_active': true,
        'created_at': nowUtc.toIso8601String(),
        'expires_at': oneHourLaterUtc.toIso8601String(),
      };

      final key = AltrApiKey.fromJson(json);

      expect(key.expiresAt, isNotNull);
      expect(key.isExpired, isFalse);
      expect(key.expiresAt!.isAfter(DateTime.now()), isTrue);

      final diff = key.expiresAt!.difference(DateTime.now());
      expect(diff.inMinutes, greaterThanOrEqualTo(50));
      expect(diff.inMinutes, lessThanOrEqualTo(65));
    });

    test('Naive ISO timestamp without Z suffix is treated as UTC and not local', () {
      // Create a UTC time 1 hour in the future, then format it naively without trailing 'Z'
      final futureUtc = DateTime.now().toUtc().add(const Duration(hours: 1));
      final naiveIsoString =
          '${futureUtc.year.toString().padLeft(4, '0')}-'
          '${futureUtc.month.toString().padLeft(2, '0')}-'
          '${futureUtc.day.toString().padLeft(2, '0')}T'
          '${futureUtc.hour.toString().padLeft(2, '0')}:'
          '${futureUtc.minute.toString().padLeft(2, '0')}:'
          '${futureUtc.second.toString().padLeft(2, '0')}';

      final json = {
        'id': 'test-naive-id',
        'name': 'Naive Key',
        'key_prefix': 'altr_live_naive...',
        'scopes': ['read'],
        'is_active': true,
        'created_at': '2026-11-02T00:00:00',
        'expires_at': naiveIsoString,
      };

      final key = AltrApiKey.fromJson(json);

      expect(key.expiresAt, isNotNull);
      expect(key.isExpired, isFalse);
      expect(key.expiresAt!.isAfter(DateTime.now()), isTrue);
    });

    test('Past expiration date is marked as expired', () {
      final pastUtc = DateTime.now().toUtc().subtract(const Duration(minutes: 15));

      final json = {
        'id': 'test-expired-id',
        'name': 'Expired Key',
        'key_prefix': 'altr_live_exp...',
        'scopes': ['read'],
        'is_active': true,
        'created_at': '2026-11-01T00:00:00Z',
        'expires_at': pastUtc.toIso8601String(),
      };

      final key = AltrApiKey.fromJson(json);

      expect(key.isExpired, isTrue);
      expect(key.expiresAt!.isBefore(DateTime.now()), isTrue);
    });
  });
}

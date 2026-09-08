import 'package:bf_stickytask/data/sync_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const goodUrl = 'https://abcdefghijklmnop.supabase.co';
  const goodKey = 'sb_publishable_AbCdEf123456';

  group('SyncConfig.problem', () {
    test('cặp URL + publishable key hợp lệ thì không có vấn đề gì', () {
      const c = SyncConfig(url: goodUrl, publishableKey: goodKey);
      expect(c.problem, isNull);
      expect(c.isNotEmpty, isTrue);
    });

    test('thiếu URL hoặc key thì báo thiếu', () {
      expect(
        const SyncConfig(url: '', publishableKey: goodKey).problem,
        contains('Supabase URL'),
      );
      expect(
        const SyncConfig(url: goodUrl, publishableKey: '').problem,
        contains('publishable key'),
      );
    });

    test('URL không phải https hoặc không parse được thì bị chặn', () {
      expect(
        const SyncConfig(url: 'http://x.supabase.co', publishableKey: goodKey)
            .problem,
        contains('https'),
      );
      expect(
        const SyncConfig(url: 'không-phải-url', publishableKey: goodKey).problem,
        contains('không hợp lệ'),
      );
    });

    test('secret key bị chặn — nó mở toàn bộ database', () {
      final problem = const SyncConfig(
        url: goodUrl,
        publishableKey: 'sb_secret_ShouldNotBeHere',
      ).problem;
      expect(problem, contains('SECRET'));
    });

    test('personal access token (sbp_) bị chặn — sai loại key', () {
      final problem = const SyncConfig(
        url: goodUrl,
        publishableKey: 'sbp_0123456789abcdef',
      ).problem;
      expect(problem, contains('Management API'));
    });

    test('legacy service_role JWT bị chặn', () {
      // header.payload.signature với payload chứa "role":"service_role"
      const jwt = 'eyJhbGciOiJIUzI1NiJ9'
          '.eyJyb2xlIjoic2VydmljZV9yb2xlIiwiaXNzIjoic3VwYWJhc2UifQ'
          '.fake-signature';
      final problem =
          const SyncConfig(url: goodUrl, publishableKey: jwt).problem;
      expect(problem, contains('service_role'));
    });

    test('anon JWT legacy vẫn được cho qua', () {
      const jwt = 'eyJhbGciOiJIUzI1NiJ9'
          '.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIn0'
          '.fake-signature';
      expect(
        const SyncConfig(url: goodUrl, publishableKey: jwt).problem,
        isNull,
      );
    });
  });

  test('sanitized bỏ khoảng trắng và dấu / cuối URL', () {
    final c = SyncConfig.sanitized(
      url: '  $goodUrl///  ',
      key: '  $goodKey \n',
    );
    expect(c.url, goodUrl);
    expect(c.publishableKey, goodKey);
    expect(c.problem, isNull);
  });

  test('projectRef lấy đúng phần đầu hostname', () {
    const c = SyncConfig(url: goodUrl, publishableKey: goodKey);
    expect(c.projectRef, 'abcdefghijklmnop');
    expect(const SyncConfig(url: '', publishableKey: '').projectRef, '');
  });

  group('chặn rò env.dart vào bản release', () {
    test('fromEnv trả rỗng khi không được phép (release build)', () {
      expect(SyncConfig.fromEnv(allowed: false), SyncConfig.empty);
      expect(SyncConfig.fromEnv(allowed: false).isEmpty, isTrue);
    });

    test('store KHÔNG fallback về env khi allowEnvFallback = false', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SyncConfigStore(allowEnvFallback: false);
      final loaded = await store.load();
      // Kể cả khi lib/env.dart trên máy dev có key thật, release phải ra rỗng.
      expect(loaded.isEmpty, isTrue);
      expect(loaded.url, isEmpty);
      expect(loaded.publishableKey, isEmpty);
    });

    test('prefs đã lưu vẫn được đọc bình thường ở release', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SyncConfigStore(allowEnvFallback: false);
      await store.save(
        const SyncConfig(url: goodUrl, publishableKey: goodKey),
      );
      final loaded = await store.load();
      expect(loaded.url, goodUrl);
      expect(loaded.publishableKey, goodKey);
    });
  });

  group('SyncConfigStore', () {
    test('save rồi load ra đúng cặp đã lưu', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SyncConfigStore();
      await store.save(
        const SyncConfig(url: goodUrl, publishableKey: goodKey),
      );
      final loaded = await store.load();
      expect(loaded.url, goodUrl);
      expect(loaded.publishableKey, goodKey);
    });

    test('clear thì rỗng và KHÔNG bị env.dart lôi lại sau khi mở app lại',
        () async {
      SharedPreferences.setMockInitialValues({
        'flutter.sync_url': goodUrl,
        'flutter.sync_publishable_key': goodKey,
      });
      final store = SyncConfigStore();
      expect((await store.load()).isNotEmpty, isTrue);

      await store.clear();

      // clear() ghi chuỗi rỗng thay vì remove, nên load() coi như "đã từng
      // cấu hình rồi ngắt" và không fallback về Env — kể cả khi env.dart có key.
      final reloaded = await store.load();
      expect(reloaded.isEmpty, isTrue);
      expect(reloaded.url, isEmpty);
      expect(reloaded.publishableKey, isEmpty);
    });
  });
}

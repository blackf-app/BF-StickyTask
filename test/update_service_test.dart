import 'package:bf_stickytask/data/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppRelease _release(String tag, {String notes = ''}) => AppRelease(
      version: normalizeVersion(tag),
      tag: tag,
      notes: notes,
      pageUrl: 'https://github.com/x/y/releases/tag/$tag',
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('normalizeVersion', () {
    test('bỏ tiền tố v, build metadata và pre-release', () {
      expect(normalizeVersion('v1.2.3'), '1.2.3');
      expect(normalizeVersion('V1.2.3'), '1.2.3');
      expect(normalizeVersion('1.2.3+7'), '1.2.3');
      expect(normalizeVersion('v1.2.3-beta.1'), '1.2.3');
      expect(normalizeVersion('  v1.0.0  '), '1.0.0');
    });
  });

  group('compareVersions', () {
    test('so theo từng thành phần số', () {
      expect(compareVersions('1.0.0', '1.0.1'), lessThan(0));
      expect(compareVersions('1.0.1', '1.0.0'), greaterThan(0));
      expect(compareVersions('1.0.0', '1.0.0'), 0);
      expect(compareVersions('1.9.0', '1.10.0'), lessThan(0));
      expect(compareVersions('2.0.0', '1.99.99'), greaterThan(0));
    });

    test('tag có v và build number vẫn so đúng', () {
      expect(compareVersions('1.0.0+1', 'v1.0.1'), lessThan(0));
      expect(compareVersions('v1.0.0', '1.0.0+9'), 0);
    });

    test('thiếu thành phần thì coi như 0', () {
      expect(compareVersions('1.1', '1.1.0'), 0);
      expect(compareVersions('1.1', '1.1.1'), lessThan(0));
      expect(compareVersions('2', '1.9.9'), greaterThan(0));
    });

    test('thành phần rác không ném lỗi', () {
      expect(compareVersions('1.x.0', '1.0.0'), 0);
      expect(compareVersions('nonsense', '0.0.0'), 0);
    });
  });

  group('AppRelease.fromJson', () {
    test('đọc tag, notes, html_url', () {
      final r = AppRelease.fromJson({
        'tag_name': 'v2.3.4',
        'body': '  sửa vài thứ  ',
        'html_url': 'https://github.com/a/b/releases/tag/v2.3.4',
      })!;
      expect(r.version, '2.3.4');
      expect(r.tag, 'v2.3.4');
      expect(r.notes, 'sửa vài thứ');
      expect(r.pageUrl, 'https://github.com/a/b/releases/tag/v2.3.4');
    });

    test('thiếu tag_name thì trả null', () {
      expect(AppRelease.fromJson({'body': 'x'}), isNull);
      expect(AppRelease.fromJson({'tag_name': '   '}), isNull);
    });

    test('thiếu html_url thì fallback về trang releases/latest', () {
      final r = AppRelease.fromJson({'tag_name': 'v1.0.0'})!;
      expect(r.pageUrl, contains('/releases/latest'));
      expect(r.notes, '');
    });

    test('đọc assets: tên, url tải, size, digest', () {
      final r = AppRelease.fromJson({
        'tag_name': 'v1.0.0',
        'assets': [
          {
            'name': 'BF-StickyTask-macos.zip',
            'browser_download_url': 'https://x/macos.zip',
            'size': 12345,
            'digest': 'sha256:ABCDEF',
          },
          {
            'name': 'app-arm64-v8a-release.apk',
            'browser_download_url': 'https://x/arm64.apk',
            'size': 999,
          },
        ],
      })!;

      expect(r.assets, hasLength(2));
      expect(r.assets[0].name, 'BF-StickyTask-macos.zip');
      expect(r.assets[0].url, 'https://x/macos.zip');
      expect(r.assets[0].size, 12345);
      // Hex về chữ thường để so trực tiếp với output của crypto.
      expect(r.assets[0].sha256, 'abcdef');
      // Không có digest thì null, chứ không phải chuỗi rỗng — verify sẽ bỏ qua.
      expect(r.assets[1].sha256, isNull);
    });

    test('asset thiếu name/url hoặc digest thuật toán khác thì bỏ', () {
      final r = AppRelease.fromJson({
        'tag_name': 'v1.0.0',
        'assets': [
          {'name': 'thieu-url.zip', 'size': 1},
          {'browser_download_url': 'https://x/thieu-name.zip', 'size': 1},
          {
            'name': 'ok.zip',
            'browser_download_url': 'https://x/ok.zip',
            'size': 1,
            // md5 chứ không phải sha256: bỏ hash, đừng so bằng hàm băm sai.
            'digest': 'md5:abc',
          },
        ],
      })!;

      expect(r.assets, hasLength(1));
      expect(r.assets.single.name, 'ok.zip');
      expect(r.assets.single.sha256, isNull);
    });

    test('không có assets thì rỗng, không null', () {
      expect(AppRelease.fromJson({'tag_name': 'v1.0.0'})!.assets, isEmpty);
    });
  });

  group('UpdateService.check', () {
    test('release mới hơn → status available', () async {
      final s = UpdateService(
        fetcher: () async => _release('v1.0.1'),
        currentVersion: '1.0.0',
      );
      await s.check();

      expect(s.status, UpdateStatus.available);
      expect(s.updateAvailable, isTrue);
      expect(s.latest!.version, '1.0.1');
      expect(s.lastCheckedAt, isNotNull);
    });

    test('release bằng hoặc cũ hơn → status upToDate', () async {
      final same = UpdateService(
        fetcher: () async => _release('v1.0.0'),
        currentVersion: '1.0.0',
      );
      await same.check();
      expect(same.status, UpdateStatus.upToDate);
      expect(same.updateAvailable, isFalse);

      final older = UpdateService(
        fetcher: () async => _release('v0.9.0'),
        currentVersion: '1.0.0',
      );
      await older.check();
      expect(older.status, UpdateStatus.upToDate);
    });

    test('chưa có release nào (null) → upToDate, không lỗi', () async {
      final s = UpdateService(
        fetcher: () async => null,
        currentVersion: '1.0.0',
      );
      await s.check();
      expect(s.status, UpdateStatus.upToDate);
      expect(s.latest, isNull);
      expect(s.error, isNull);
    });

    test('UpdateException → status error, giữ message tiếng Việt', () async {
      final s = UpdateService(
        fetcher: () async => throw const UpdateException('repo private'),
        currentVersion: '1.0.0',
      );
      await s.check();
      expect(s.status, UpdateStatus.error);
      expect(s.error, 'repo private');
      expect(s.updateAvailable, isFalse);
    });

    test('lỗi lạ cũng không ném ra ngoài', () async {
      final s = UpdateService(
        fetcher: () async => throw StateError('bể'),
        currentVersion: '1.0.0',
      );
      await s.check();
      expect(s.status, UpdateStatus.error);
      expect(s.error, contains('Không kiểm được bản mới'));
    });

    test('không đọc được version đang chạy thì KHÔNG báo có bản mới', () async {
      // Nếu so với chuỗi rỗng thì mọi release đều "mới hơn" → popup mỗi lần mở.
      final s = UpdateService(
        fetcher: () async => _release('v1.0.1'),
        currentVersion: '',
      );
      await s.check();
      expect(s.status, UpdateStatus.upToDate);
      expect(s.latest, isNotNull);
    });

    test('notifyListeners chạy khi status đổi', () async {
      final s = UpdateService(
        fetcher: () async => _release('v1.0.1'),
        currentVersion: '1.0.0',
      );
      var n = 0;
      s.addListener(() => n++);
      await s.check();
      // Ít nhất 2: một lần vào checking, một lần ra kết quả.
      expect(n, greaterThanOrEqualTo(2));
    });
  });

  group('UpdateService.checkOnStartup', () {
    test('có bản mới chưa bỏ qua → trả release để bật popup', () async {
      final s = UpdateService(
        fetcher: () async => _release('v1.0.1'),
        currentVersion: '1.0.0',
      );
      await s.load();
      expect((await s.checkOnStartup())?.version, '1.0.1');
    });

    test('đang là bản mới nhất → không bật popup', () async {
      final s = UpdateService(
        fetcher: () async => _release('v1.0.0'),
        currentVersion: '1.0.0',
      );
      await s.load();
      expect(await s.checkOnStartup(), isNull);
    });

    test('lỗi mạng lúc mở app → im lặng, không popup', () async {
      final s = UpdateService(
        fetcher: () async => throw const UpdateException('mất mạng'),
        currentVersion: '1.0.0',
      );
      await s.load();
      expect(await s.checkOnStartup(), isNull);
      // Trạng thái vẫn ghi lại để nút trên title bar / dialog hiện được.
      expect(s.status, UpdateStatus.error);
    });

    test('đã bỏ qua bản đó → không popup nữa, nhưng check() vẫn báo',
        () async {
      final s = UpdateService(
        fetcher: () async => _release('v1.0.1'),
        currentVersion: '1.0.0',
      );
      await s.load();
      expect(await s.checkOnStartup(), isNotNull);

      await s.skipLatest();
      expect(s.skippedVersion, '1.0.1');
      expect(await s.checkOnStartup(), isNull);

      // Bấm tay thì vẫn phải thấy có bản mới.
      await s.check();
      expect(s.updateAvailable, isTrue);
    });

    test('bỏ qua 1.0.1 rồi ra 1.0.2 thì popup lại', () async {
      SharedPreferences.setMockInitialValues({
        'update_skipped_version': '1.0.1',
      });
      final s = UpdateService(
        fetcher: () async => _release('v1.0.2'),
        currentVersion: '1.0.0',
      );
      await s.load();
      expect(s.skippedVersion, '1.0.1');
      expect((await s.checkOnStartup())?.version, '1.0.2');
    });

    test('version đã bỏ qua sống qua lần mở app sau', () async {
      final first = UpdateService(
        fetcher: () async => _release('v1.0.1'),
        currentVersion: '1.0.0',
      );
      await first.load();
      await first.check();
      await first.skipLatest();

      // Mở app lại: đọc lại prefs từ đầu.
      final second = UpdateService(
        fetcher: () async => _release('v1.0.1'),
        currentVersion: '1.0.0',
      );
      await second.load();
      expect(second.skippedVersion, '1.0.1');
      expect(await second.checkOnStartup(), isNull);
    });
  });

  test('releasePageUrl có fallback khi chưa kiểm được gì', () {
    final s = UpdateService(fetcher: () async => null, currentVersion: '1.0.0');
    expect(s.releasePageUrl, 'https://github.com/$kUpdateRepo/releases/latest');
  });
}

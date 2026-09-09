import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bf_stickytask/data/update_installer.dart';
import 'package:bf_stickytask/data/update_service.dart';
import 'package:bf_stickytask/data/updater.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/fake_installer.dart';

/// `test()` chứ không `testWidgets()`: [Updater] tải thật ra file tạm, mà
/// `testWidgets` chạy trong `FakeAsync` — future của `dart:io` không bao giờ
/// complete trong đó. Phần UI được test ở `update_dialog_test.dart`.

final Uint8List _payload = Uint8List.fromList(utf8.encode('bản mới đây'));
final String _payloadSha = sha256.convert(_payload).toString();

AppRelease _release({List<ReleaseAsset>? assets}) => AppRelease(
      version: '1.4.0',
      tag: 'v1.4.0',
      notes: '',
      pageUrl: 'https://example.test/releases/tag/v1.4.0',
      assets: assets ??
          [
            ReleaseAsset(
              name: 'BF-StickyTask-macos.zip',
              url: 'https://example.test/BF-StickyTask-macos.zip',
              size: _payload.length,
              sha256: _payloadSha,
            ),
          ],
    );

class _StubClient extends http.BaseClient {
  _StubClient({
    Uint8List? body,
    this.statusCode = 200,
    this.contentLength,
    this.chunks = 1,
  }) : body = body ?? _payload;

  final Uint8List body;
  final int statusCode;

  /// `null` = giả server không trả Content-Length.
  final int? contentLength;

  /// Chia body thành mấy chunk — để kiểm progress cộng dồn.
  final int chunks;

  int calls = 0;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    final size = (body.length / chunks).ceil();
    final stream = Stream<List<int>>.fromIterable([
      for (var i = 0; i < body.length; i += size)
        body.sublist(i, i + size > body.length ? body.length : i + size),
    ]);
    return http.StreamedResponse(
      stream,
      statusCode,
      contentLength: contentLength ?? body.length,
    );
  }

  @override
  void close() => closed = true;
}

void main() {
  group('formatBytes', () {
    test('đổi đơn vị theo mốc 1024', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(5 * 1024 * 1024 + 512 * 1024), '5.5 MB');
      expect(formatBytes(2 * 1024 * 1024 * 1024), '2.0 GB');
    });

    test('bỏ số thập phân từ 100 trở lên để không tràn dòng', () {
      expect(formatBytes(150 * 1024 * 1024), '150 MB');
    });
  });

  group('Updater.run', () {
    test('tải → verify → cài, rồi yêu cầu thoát app', () async {
      final installer = FakeInstaller();
      final client = _StubClient();
      var quits = 0;
      final updater = Updater(
        installer: installer,
        clientFactory: () => client,
        onQuit: () async => quits++,
      );

      await updater.run(_release());

      expect(updater.phase, UpdatePhase.handedOff);
      expect(updater.error, isNull);
      expect(installer.installCalls, 1);
      expect(installer.installedVersion, '1.4.0');
      expect(await installer.installed!.readAsBytes(), _payload);
      expect(quits, 1);
      // Client phải được đóng, không thì socket treo lại sau mỗi lần cập nhật.
      expect(client.closed, isTrue);
    });

    test('quitsApp = false (Android) thì không thoát app', () async {
      final installer = FakeInstaller(quitsApp: false);
      var quits = 0;
      final updater = Updater(
        installer: installer,
        clientFactory: _StubClient.new,
        onQuit: () async => quits++,
      );

      await updater.run(_release());

      expect(installer.installCalls, 1);
      expect(quits, 0);
      expect(updater.phase, UpdatePhase.handedOff);
    });

    test('progress cộng dồn theo chunk', () async {
      final updater = Updater(
        installer: FakeInstaller(),
        clientFactory: () => _StubClient(chunks: 4),
        onQuit: () async {},
      );

      final seen = <int>[];
      updater.addListener(() {
        if (updater.phase == UpdatePhase.downloading) {
          seen.add(updater.received);
        }
      });

      await updater.run(_release());

      // Lần đầu là 0 (chuyển sang downloading), sau đó tăng dần tới hết.
      expect(seen.first, 0);
      expect(seen.last, _payload.length);
      expect(seen, orderedEquals(seen.toList()..sort()));
      expect(updater.total, _payload.length);
    });

    test('không có Content-Length thì progress = null', () async {
      final updater = Updater(
        installer: FakeInstaller(),
        // size = 0 ở asset và server cũng không trả Content-Length.
        clientFactory: () => _StubClient(contentLength: 0),
        onQuit: () async {},
      );

      await updater.run(_release(
        assets: [
          ReleaseAsset(
            name: 'BF-StickyTask-macos.zip',
            url: 'https://example.test/a.zip',
            size: 0,
          ),
        ],
      ));

      expect(updater.total, 0);
      expect(updater.progress, isNull);
      expect(updater.phase, UpdatePhase.handedOff);
    });

    test('HTTP lỗi thì báo lỗi, không gọi installer', () async {
      final installer = FakeInstaller();
      final updater = Updater(
        installer: installer,
        clientFactory: () => _StubClient(statusCode: 404),
        onQuit: () async {},
      );

      await updater.run(_release());

      expect(updater.phase, UpdatePhase.error);
      expect(updater.error, contains('404'));
      expect(installer.installCalls, 0);
    });

    test('sha256 không khớp thì không cài', () async {
      final installer = FakeInstaller();
      final updater = Updater(
        installer: installer,
        clientFactory: () =>
            _StubClient(body: Uint8List.fromList(utf8.encode('file rác'))),
        onQuit: () async {},
      );

      await updater.run(_release(
        assets: [
          ReleaseAsset(
            name: 'BF-StickyTask-macos.zip',
            url: 'https://example.test/a.zip',
            // size khớp với 'file rác' nhưng hash thì không.
            size: utf8.encode('file rác').length,
            sha256: _payloadSha,
          ),
        ],
      ));

      expect(updater.phase, UpdatePhase.error);
      expect(updater.error, contains('sha256'));
      expect(installer.installCalls, 0);
    });

    test('installer ném lỗi thì lỗi lên tới UI, app không thoát', () async {
      var quits = 0;
      final updater = Updater(
        installer: FakeInstaller(
          throwOnInstall: const UpdateException('Cần quyền admin.'),
        ),
        clientFactory: _StubClient.new,
        onQuit: () async => quits++,
      );

      await updater.run(_release());

      expect(updater.phase, UpdatePhase.error);
      expect(updater.error, 'Cần quyền admin.');
      expect(quits, 0);
    });

    test('release không có asset cho máy này thì báo rõ', () async {
      final installer = FakeInstaller(assetNeedle: null);
      final updater = Updater(
        installer: installer,
        clientFactory: _StubClient.new,
        onQuit: () async {},
      );

      await updater.run(_release());

      expect(updater.phase, UpdatePhase.error);
      expect(updater.error, contains('không có bản build cho máy này'));
      expect(installer.installCalls, 0);
    });

    test('nền tảng không hỗ trợ: supported = false, run báo lỗi', () async {
      final client = _StubClient();
      final updater = Updater(
        // Linux chẳng hạn: forCurrentPlatform() trả null.
        installer: null,
        clientFactory: () => client,
        onQuit: () async {},
      );

      expect(updater.supported, isFalse);
      expect(updater.canInstall(_release()), isFalse);
      expect(updater.handoffMessage, isEmpty);

      await updater.run(_release());

      expect(updater.phase, UpdatePhase.error);
      expect(updater.error, contains('chưa tự cài được'));
      // Không tải gì cả khi biết chắc không cài được.
      expect(client.calls, 0);
    });

    test('không tải lại khi đang chạy', () async {
      final client = _StubClient();
      final updater = Updater(
        installer: FakeInstaller(quitsApp: false),
        clientFactory: () => client,
        onQuit: () async {},
      );

      // Hai lần gọi song song: lần sau phải bị bỏ qua vì đang busy.
      await Future.wait([updater.run(_release()), updater.run(_release())]);

      expect(client.calls, 1);
    });

    test('lỗi thì không để lại thư mục tạm nào', () async {
      int tempDirs() => Directory.systemTemp
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.contains('bfst-download-'))
          .length;

      final before = tempDirs();
      // Ba đường lỗi ở ba giai đoạn khác nhau, cả ba đều phải dọn.
      for (final updater in [
        // Lỗi trước khi có file: ném trong _download.
        Updater(
          installer: FakeInstaller(),
          clientFactory: () => _StubClient(statusCode: 500),
          onQuit: () async {},
        ),
        // Lỗi sau khi có file: ném ở verify.
        Updater(
          installer: FakeInstaller(),
          clientFactory: () =>
              _StubClient(body: Uint8List.fromList(utf8.encode('rác'))),
          onQuit: () async {},
        ),
        // Lỗi ở bước cài.
        Updater(
          installer: FakeInstaller(
            throwOnInstall: const UpdateException('x'),
          ),
          clientFactory: _StubClient.new,
          onQuit: () async {},
        ),
      ]) {
        await updater.run(_release());
        expect(updater.phase, UpdatePhase.error);
      }

      expect(tempDirs(), before);
    });

    test('reset đưa về idle để bấm lại sau khi lỗi', () async {
      final updater = Updater(
        installer: FakeInstaller(),
        clientFactory: () => _StubClient(statusCode: 500),
        onQuit: () async {},
      );

      await updater.run(_release());
      expect(updater.phase, UpdatePhase.error);

      updater.reset();
      expect(updater.phase, UpdatePhase.idle);
      expect(updater.error, isNull);
      expect(updater.received, 0);
    });
  });

  group('verifyDownload', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('bfst-verify-');
    });

    tearDown(() async => dir.delete(recursive: true));

    Future<File> write(List<int> bytes) async {
      final f = File('${dir.path}/asset.bin');
      await f.writeAsBytes(bytes);
      return f;
    }

    test('size khớp + không có digest thì bỏ qua hash', () async {
      final file = await write(_payload);
      await expectLater(
        verifyDownload(
          file,
          ReleaseAsset(name: 'a', url: 'u', size: _payload.length),
        ),
        completes,
      );
    });

    test('size = 0 (GitHub không trả) thì không chặn', () async {
      final file = await write(_payload);
      await expectLater(
        verifyDownload(file, const ReleaseAsset(name: 'a', url: 'u', size: 0)),
        completes,
      );
    });

    test('size lệch thì ném lỗi trước khi băm', () async {
      final file = await write(_payload);
      var hashed = false;
      await expectLater(
        verifyDownload(
          file,
          ReleaseAsset(
            name: 'a',
            url: 'u',
            size: _payload.length + 1,
            sha256: _payloadSha,
          ),
          hasher: (_) async {
            hashed = true;
            return _payloadSha;
          },
        ),
        throwsA(isA<UpdateException>()),
      );
      expect(hashed, isFalse);
    });

    test('digest khớp thì qua', () async {
      final file = await write(_payload);
      await expectLater(
        verifyDownload(
          file,
          ReleaseAsset(
            name: 'a',
            url: 'u',
            size: _payload.length,
            sha256: _payloadSha,
          ),
        ),
        completes,
      );
    });

    test('digest lệch thì ném lỗi', () async {
      final file = await write(_payload);
      await expectLater(
        verifyDownload(
          file,
          ReleaseAsset(
            name: 'a',
            url: 'u',
            size: _payload.length,
            sha256: 'deadbeef',
          ),
        ),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            contains('sha256'),
          ),
        ),
      );
    });
  });
}

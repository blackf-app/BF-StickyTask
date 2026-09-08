# BF-StickyTask

Sticker-note nổi trên mọi app khác, để note các task cần làm tiếp theo.
macOS · Windows · Android — một codebase Flutter, đồng bộ qua Supabase.

| Tab | Làm được gì |
|-----|-------------|
| **Current** | thêm, sửa inline, xoá, kéo đổi thứ tự, tick done |
| **History** | việc đã xong (mới nhất trên đầu), **lọc theo ngày**, restore về Current, xoá hẳn, xoá cả tab |

**Mọi thao tác xoá đều có popup xác nhận** — xoá 1 việc ở Current, xoá hẳn ở History,
"Xoá hết" cả tab History, và "Ngắt" đồng bộ (thao tác đó xoá URL + key đã lưu).
Popup hiện lại đúng nội dung dòng đang bị xoá để không bấm nhầm dòng.
Tất cả đi qua `confirmDelete()` trong [lib/ui/confirm_dialog.dart](lib/ui/confirm_dialog.dart)
— thêm thao tác xoá mới thì gọi hàm đó, đừng dựng AlertDialog riêng.

Tab History có hàng chip lọc theo ngày — **Tất cả · Hôm nay · 7 ngày · 30 ngày · Chọn ngày**
(khoảng tự chọn qua lịch). Đang lọc thì tiêu đề đổi thành `3/12 việc đã xong`, và **"Xoá hết"
chỉ xoá đúng những dòng đang hiện** — popup xác nhận nói rõ điều đó. Bộ lọc chỉ sống trong
phiên chạy: mở lại app là về "Tất cả", để không bao giờ mở app ra thấy History trống mà không
hiểu vì sao. Mốc so sánh là `doneAt` quy về **giờ địa phương** (note lưu UTC), nên "hôm nay"
đúng theo lịch của máy đang xem.

Giao diện có 3 mode — **tự động theo hệ thống / sáng / tối** — đổi bằng nút hình mặt trời/mặt trăng
trên title bar (xoay vòng `system → light → dark`), có trên cả desktop và Android, và được nhớ lại
sau khi tắt app. Bảng màu tối giữ tông nâu ấm để vẫn ra dáng giấy note.

## Chạy lần đầu

```bash
export PATH="$HOME/development/flutter/bin:$PATH"   # nếu chưa có trong PATH
flutter pub get
flutter run -d macos        # hoặc: -d windows | -d <android-device-id>
```

Cấu hình Supabase nhập **trong app** (icon mây trên title bar), không phải trong code
— xem [mục Backend](#backend). Chưa cấu hình thì app chạy thuần local, icon mây gạch chéo.

`lib/env.dart` (gitignore) chỉ còn là **giá trị điền sẵn cho lần chạy đầu**, tiện cho máy dev:

```bash
cp lib/env.example.dart lib/env.dart   # rồi điền supabaseUrl + publishable key
```

Bỏ qua file đó hoàn toàn cũng được. Prefs thắng env.dart ngay khi bấm Lưu, và bấm
**Ngắt** thì env.dart không lôi cấu hình lại nữa.

## Phím & thao tác desktop

| | |
|---|---|
| `⌥⇧S` (macOS) / `Alt+Shift+S` (Windows) | ẩn/hiện cửa sổ — chạy được cả khi app không focus |
| `Esc` | đang sửa dòng → huỷ sửa; không sửa gì → ẩn cửa sổ |
| `Enter` | ô dưới cùng: thêm việc mới; đang sửa dòng: lưu |
| nút mặt trời/mặt trăng | đổi giao diện: tự động theo hệ thống → sáng → tối |
| icon mũi tên vòng / tải xuống | kiểm tra cập nhật (xem [mục Cập nhật](#cập-nhật)) |
| icon tên lửa | bật/tắt **mở app khi khởi động máy** (xem [mục dưới](#mở-app-khi-khởi-động-máy)) |
| icon ghim trên title bar | bật/tắt always-on-top |
| icon `—` | ẩn cửa sổ (app vẫn chạy trong tray) |
| bấm icon Dock (macOS) | hiện lại cửa sổ đang ẩn |
| click icon tray (Windows/Linux) | ẩn/hiện · right-click → menu (gồm **Thoát**) |

Vị trí + kích thước cửa sổ và trạng thái ghim được nhớ qua các lần mở.

**macOS không có icon menu bar.** `tray_manager` 0.5.3 không forward mouse event trên macOS
(phần code đó bị comment trong plugin) và `setContextMenu` không gắn menu vào status item → icon
đó hoàn toàn vô tác dụng, nên đã bỏ. Lấy lại cửa sổ đang ẩn bằng `⌥⇧S` hoặc bấm icon ở Dock
(`applicationShouldHandleReopen` trong [AppDelegate.swift](macos/Runner/AppDelegate.swift)).

**Gotcha macOS đã sửa:** template Flutter đặt `applicationShouldTerminateAfterLastWindowClosed`
= `true`, còn `windowManager.hide()` trên macOS là `orderOut` → **ẩn cửa sổ là app tự thoát**.
`AppDelegate` trả về `false` để app sống tiếp khi ẩn. Đừng đổi lại giá trị đó.

Android: không có always-on-top (Android không cho app thường nổi trên app khác),
app chạy như app bình thường.

## Mở app khi khởi động máy

Nút **tên lửa** trên title bar (và checkbox *"Mở khi khởi động máy"* trong menu tray của
Windows) bật/tắt việc OS tự chạy app lúc đăng nhập. Trạng thái thật nằm ở **OS chứ không ở
prefs**, nên app đọc lại mỗi lần mở — user tắt nó ở System Settings / Task Manager thì nút
tự về đúng trạng thái. Logic chung ở
[`lib/app/launch_at_startup.dart`](lib/app/launch_at_startup.dart), hai nền tảng đi hai
đường khác hẳn:

**macOS — `SMAppService.mainApp`** ([`macos/Runner/LaunchAtLogin.swift`](macos/Runner/LaunchAtLogin.swift)).
App chạy **sandbox** nên **không ghi được `~/Library/LaunchAgents`** — cách mà hầu hết plugin
Flutter dùng, và trong sandbox nó *chết câm*: ghi file báo thành công vào container ảo, khởi
động lại thì không có gì chạy. `SMAppService` là API Apple làm riêng cho login item của app
sandbox, không cần entitlement thêm.

- Cần **macOS 13+**. Deployment target của project là 12.0 và trong sandbox không còn đường
  nào khác cho macOS 12 → ở đó native trả `supported = false` và **nút tự ẩn**, chứ không
  hiện một nút bấm không lên.
- Status `.requiresApproval` (user từng từ chối, hoặc macOS còn chờ duyệt) vẫn tính là "đang
  bật" nhưng nút chuyển **màu đỏ** + tooltip chỉ đường
  **System Settings → General → Login Items**. Không nói ra thì user thấy nút sáng mà máy
  khởi động lại chẳng thấy app đâu.
- Login item trỏ vào **đúng bản `.app` lúc bấm bật**. Chuyển app sang chỗ khác
  (`~/Downloads` → `/Applications`) thì tắt–bật lại một lần.

**Windows — registry `HKCU\…\CurrentVersion\Run`**, ghi thẳng bằng Dart (`win32_registry`),
không cần code C++ trong runner.

- Giá trị là đường dẫn exe bọc ngoặc kép. App cập nhật hoặc bị chuyển thư mục thì lần mở sau
  app **tự ghi lại đường dẫn mới** — không bắt user tắt–bật lại nút.
- Có kiểm cả `…\Explorer\StartupApproved\Run`: byte đầu **lẻ** = user đã tắt ở
  **Task Manager → Startup**. Bỏ qua chỗ này là app báo "đang bật" trong khi Windows đã chặn.
  Bật lại trong app thì ghi đè byte đó về 2 (cho chạy).

App **không** tự ẩn khi được OS mở: khởi động máy xong là thấy luôn cửa sổ note.
Android/Linux không có tính năng này.

## Backend

Một bảng `public.notes` trên Supabase. **Không có đăng nhập** — client chỉ cần
Supabase URL + publishable key.

1. Dashboard → **SQL Editor** → chạy [`supabase/schema.sql`](supabase/schema.sql).
2. Dashboard → **Project Settings → API keys** → copy **publishable key**
   (`sb_publishable_…`).
3. Trong app: bấm icon mây trên title bar → dán URL + key → **Lưu & đồng bộ**.
   Cấu hình được lưu vào SharedPreferences, chỉ phải nhập một lần mỗi máy.

Máy nào nhập cùng cặp URL + key là thấy cùng một tập note. Không có khái niệm
user: bảng là một danh sách dùng chung.

### ⚠️ Mô hình bảo mật — đọc trước khi dùng cho việc thật

Publishable key là bản thay thế cho anon key legacy và nó **là key công khai**:
nó không mang danh tính user, nên `auth.uid()` luôn NULL và RLS **không thể**
scope theo user. `schema.sql` vì thế mở bảng `notes` cho role `anon`.

Hệ quả: **ai có project ref + publishable key đều đọc/ghi được toàn bộ note.**
Ranh giới bảo mật duy nhất là giữ kín hai thứ đó. Đừng đặt bảng nào khác vào
project này, và đừng dùng nó cho dữ liệu cần riêng tư thật.

Muốn kín hơn thì phải quay lại có danh tính — hoặc login lại, hoặc thêm một
"sync code" bí mật và scope RLS theo header. Cả hai đều là thay đổi schema.

App **chặn** dán sai loại key (`sb_secret_…`, `sbp_…`, service_role JWT) vì
secret key mở toàn bộ database — xem `SyncConfig.problem`.

### App báo "Không kết nối được" — soi bằng script

```bash
bash tools/check-backend.sh                      # lấy URL+key app đang dùng
bash tools/check-backend.sh <url> <publishable>  # hoặc chỉ định tay
```

Nó kiểm 4 thứ theo đúng thứ tự và in ra cái nào chưa xong: key có được nhận,
bảng `notes` có tồn tại, **schema đã migrate chưa** (còn cột `user_id` là chưa),
và ghi có qua được RLS. Có bước nào đỏ thì script in luôn link SQL Editor của
đúng project đó.

Lỗi hay gặp nhất là `42501 row-level security`: bảng vẫn đang là bản cũ với RLS
theo `auth.uid()`, mà app thì không đăng nhập ⇒ `auth.uid()` NULL ⇒ chặn hết.
Chạy `supabase/schema.sql` là xong; nó tự drop policy cũ + cột `user_id`.

### Cơ chế đồng bộ

Local-first: mọi thao tác ghi vào RAM + `notes.json` ngay, UI không bao giờ chờ mạng.

- **push** — note có cờ `dirty` được upsert lên server (debounce 800ms sau thay đổi)
- **pull** — `select … where updated_at >= lastPull`, con trỏ là `updated_at` lớn nhất đã thấy
- **realtime** — subscribe `postgres_changes`, máy khác tick done là máy này đổi ngay
- **merge** — last-write-wins từng row theo `updated_at`; bằng nhau thì giữ bản local
- **offline** — lỗi mạng thì `dirty` vẫn nằm đó, tự đẩy lại ở lần sync sau (định kỳ 60s,
  khi app resume, hoặc bấm "Đồng bộ ngay")
- **xoá** — tombstone `deleted = true` (không DELETE thật) để lệnh xoá lan sang máy khác;
  tombstone đã sync + cũ hơn 30 ngày sẽ được dọn khỏi file local

`updated_at` do client ghi nên **đồng hồ máy phải đúng** — một máy lệch giờ nhiều sẽ luôn
thắng khi merge.

## Cập nhật

App tự kiểm bản mới **khi mở** và hiện popup nếu có, ngoài ra có nút kiểm tay
trên title bar (icon mũi tên vòng; đổi thành icon tải xuống + màu accent khi
đang có bản mới chờ).

Nguồn là **GitHub Releases** của chính repo này:

```
GET https://api.github.com/repos/blackf-app/BF-StickyTask/releases/latest
```

- **Không token.** Repo phải là **public**, không thì GitHub trả 404 và tính
  năng chết câm. Đừng "sửa" bằng cách nhúng PAT vào app: `strings` là ra ngay,
  đúng thứ [`tools/scan-secrets.sh`](tools/scan-secrets.sh) tồn tại để chặn.
- **So version** lấy từ `pubspec.yaml` (qua `package_info_plus`) với `tag_name`
  của release. Tag `v1.0.1`, build metadata `1.0.1+7`, pre-release `1.0.1-beta`
  đều quy về `1.0.1` rồi so từng thành phần số.
- **Không tự tải, không tự cài.** Popup hiện release notes + nút mở trang
  release trên browser để tự tải bản đúng máy. Tự ghi đè app đang chạy là việc
  khác hẳn: macOS chạy sandbox không tự thay `.app` được, Windows cần helper
  process riêng.
- **"Bỏ qua bản này"** ghi version vào SharedPreferences (`update_skipped_version`)
  nên lần mở app sau không popup lại — nhưng bấm nút kiểm tay thì vẫn báo.
- **Lỗi mạng lúc mở app thì im lặng**, không ai muốn vừa mở app đã ăn popup lỗi.
  Trạng thái vẫn nằm trong `UpdateService` để popup hiện khi user tự mở.

`/releases/latest` bỏ qua draft và pre-release, nên muốn user thấy bản mới thì
release phải được publish thật. Cách ra bản mới:

```bash
# 1. nâng version trong pubspec.yaml, ví dụ: version: 1.0.1+2
# 2. commit rồi push tag — workflow release.yml build 3 nền tảng + tạo release
git tag v1.0.1 && git push origin v1.0.1
```

Tag phải khớp version trong `pubspec.yaml`, không thì máy đang chạy bản cũ so ra
sai. Android 11+ cần khối `<queries>` với `android.intent.action.VIEW` + scheme
`https` trong `AndroidManifest.xml` — thiếu là `url_launcher` không thấy browser
nào và nút "Tải bản mới" không mở được trang.

## Cấu trúc

```
lib/
  main.dart                    bootstrap: cửa sổ → Supabase → repo → runApp
  env.dart                     giá trị điền sẵn lần đầu, tuỳ chọn (gitignore)
  models/note.dart             Note + JSON local + row Supabase
  data/local_store.dart        đọc/ghi notes.json (ghi atomic qua file .tmp)
  data/note_repo.dart          nguồn sự thật: CRUD, done/restore, reorder, merge LWW
  data/sync_config.dart        SyncConfig (URL + publishable key) + đọc/ghi prefs
  data/sync_service.dart       push/pull/realtime (không có auth)
  data/update_service.dart     kiểm bản mới trên GitHub Releases + so version
  app/desktop_integration.dart cửa sổ, always-on-top, tray, hotkey, nhớ vị trí
  app/launch_at_startup.dart   mở app khi khởi động máy (macOS SMAppService / Windows registry)
  app/history_filter.dart      bộ lọc ngày của tab History (preset + khoảng tự chọn)
  app/settings_controller.dart themeMode (system/light/dark), lưu SharedPreferences
  app/theme.dart               bảng màu giấy note bản sáng + bản tối, context.paper
  ui/home_page.dart            title bar + 2 tab + ô thêm việc
  ui/note_tile.dart            dòng note (Current / History) + editor inline
  ui/sync_dialog.dart          popup trạng thái đồng bộ + form URL/key
  ui/update_dialog.dart        popup cập nhật: version, release notes, nút tải
  ui/confirm_dialog.dart       confirmDelete() — popup xác nhận cho mọi thao tác xoá
macos/Runner/LaunchAtLogin.swift  phía native của "mở khi khởi động máy" (SMAppService)
supabase/schema.sql            bảng + RLS + realtime
tools/patch-flutter-sdk.sh     vá Flutter SDK để build được Android (xem mục Build)
tools/migrate-container.sh     chuyển notes.json + prefs sang container của bundle id mới
tools/check-backend.sh         soi backend: bảng, schema đã migrate chưa, quyền ghi
tools/build-release.sh         build release KHÔNG nhúng env.dart + soi lại binary
tools/scan-secrets.sh          soi binary xem có nhúng Supabase URL/key thật không
tools/gen-icons.py             sinh icon app cho macOS/Windows/Android từ một bản vẽ
supabase/cron-purge-tombstones.sql  pg_cron dọn tombstone hằng ngày
```

## Đổi tên & bundle id

Project từng tên là `stickytask` / `vn.easygoing.stickytask`. Bản hiện tại:

| | |
|---|---|
| Tên hiển thị | **BF-StickyTask** (macOS `PRODUCT_NAME`, Windows `ProductName`, Android `android:label`) |
| Dart package | `bf_stickytask` (import trong `test/` là `package:bf_stickytask/...`) |
| Bundle id / applicationId | `com.blackface.bfstickytask` |
| Exe Windows | `bf_stickytask.exe` (`BINARY_NAME` trong `windows/CMakeLists.txt`) |

App macOS chạy **sandbox**, nên `getApplicationSupportDirectory()` nằm trong container của
bundle id. Đổi bundle id ⇒ đổi container ⇒ app mới **không có quyền** đọc container cũ, migration
không thể làm trong Dart. Dùng script ngoài sandbox:

```bash
bash tools/migrate-container.sh          # copy notes.json + prefs sang container mới
bash tools/migrate-container.sh --force  # ghi đè nếu đích đã có dữ liệu
```

Container cũ (`~/Library/Containers/vn.easygoing.stickytask`) không bị xoá — giữ làm backup,
tự xoá tay khi đã chắc app mới chạy đúng.

## Dọn tombstone trên server (pg_cron)

Xoá note là ghi `deleted = true` chứ không DELETE — tombstone là thứ mang lệnh xoá
sang máy khác. Máy nào còn note đó mà không thấy tombstone thì lần push sau nó
**đẩy note lên lại**. Client tự dọn tombstone khỏi file local sau 30 ngày
(`_tombstoneTtl`, `note_repo.dart`), nhưng **server thì không** — bảng sẽ tích rác mãi.

Bật dọn tự động: SQL Editor → chạy [`supabase/cron-purge-tombstones.sql`](supabase/cron-purge-tombstones.sql).

Job `purge-deleted-notes` chạy **00:00 giờ VN mỗi ngày** (`0 17 * * *`, vì pg_cron
trên Supabase theo UTC) và xoá cứng tombstone **cũ hơn 30 ngày** — khớp TTL của
client. Cửa sổ giữ 30 ngày là cố ý: xoá tombstone sớm hơn thời gian một máy có thể
offline thì note đã xoá sẽ sống lại từ máy đó.

```sql
select public.purge_deleted_notes();                  -- dọn ngay, giữ 30 ngày
select public.purge_deleted_notes(interval '0');      -- dọn sạch (chấp nhận rủi ro)
select * from cron.job where jobname = 'purge-deleted-notes';
```

## Đưa app cho người khác dùng

App **không** gắn chết với project nào — người nhận tạo Supabase project riêng,
chạy `supabase/schema.sql`, rồi dán URL + publishable key của họ vào app.

Vì RLS mở (`using (true)`), **mỗi người phải một project riêng**. Chung project là
chung luôn danh sách note, không tách theo user được.

### ⚠️ Build cho người khác thì phải dùng tools/build-release.sh

`Env` là `const String` nên giá trị trong `lib/env.dart` **bị compile vào snapshot
Dart**. Đã kiểm chứng: build khi env.dart còn giá trị thì cả
`App.framework/…/kernel_blob.bin` (macOS) lẫn `assets/flutter_assets/kernel_blob.bin`
(APK) đều chứa project ref + publishable key. Người nhận bản đó sẽ **tự nối vào
project của bạn** ngay lần mở đầu, và `strings` là ra key.

Code đã chặn phần ĐỌC env.dart ở release (`SyncConfig.fromEnv` → `kDebugMode`),
nhưng chuỗi const vẫn có thể nằm lại trong binary. Nên build bằng:

```bash
bash tools/build-release.sh macos
bash tools/build-release.sh apk --split-per-abi
```

Script tạm thay `lib/env.dart` bằng bản rỗng, build, trả file về (kể cả khi fail
hoặc Ctrl-C), rồi **soi lại binary** bằng [`tools/scan-secrets.sh`](tools/scan-secrets.sh)
và fail nếu tìm thấy key/URL thật. CI dùng đúng script đó — logic soi để một chỗ
vì trước đây regex bị copy ra 3 nơi rồi lệch nhau (CI fail, script local báo
"sạch" trên đúng cùng một binary).

Soi tay file nào cũng được:

```bash
bash tools/scan-secrets.sh <file>...   # exit 0 = sạch, 1 = có dấu vết
```

Nó chỉ khớp **giá trị thật** — `sb_publishable_`/`sb_secret_` kèm >=10 ký tự, và
>=16 ký tự `[a-z0-9]` liền trước `.supabase.co` (project ref thật dài 20). Nhờ vậy
placeholder `https://<project-ref>.supabase.co` trong hintText của form không bị
tính là rò.

## Build bản phát hành

```bash
flutter build macos     # build/macos/Build/Products/Release/BF-StickyTask.app
flutter build windows   # phải build trên máy Windows (cần VS 2022 + Desktop C++)
flutter build apk       # xem mục Android bên dưới trước
```

Bản macOS không ký/notarize (dùng cá nhân). Copy `.app` sang máy khác mà bị chặn:

```bash
xattr -dr com.apple.quarantine /Applications/BF-StickyTask.app
```

### Android: 2 thứ phải làm trước

**1. JDK.** Cần JDK 17+ cho Gradle. Máy này đã cài Temurin 21 ở `~/development/jdk/jdk-21.0.12.1+1`
và `~/.zshrc` đã export `JAVA_HOME`. Máy mới thì cài JDK rồi `flutter config --jdk-dir=<path>`.

**2. Vá Flutter SDK.**

```bash
bash tools/patch-flutter-sdk.sh
```

Flutter 3.47.2 **không build được Android cho bất kỳ project nào** — kể cả project `flutter create`
trắng. `flutter.groovy` trong SDK import class Kotlin cùng included-build
(`com.flutter.gradle.BaseApplicationNameHandler`) nhưng Gradle không đưa output của `compileKotlin`
vào classpath của `compileGroovy`, nên fail ở task `:gradle:compileGroovy`
(upstream: [flutter#173943](https://github.com/flutter/flutter/issues/173943),
[flutter#176077](https://github.com/flutter/flutter/issues/176077)).

Patch nằm trong SDK nên **`flutter upgrade` sẽ xoá** → chạy lại script sau mỗi lần upgrade.
Script idempotent, và tự báo nếu upstream đã sửa. Bỏ patch:

```bash
cd ~/development/flutter && git checkout -- packages/flutter_tools/gradle/build.gradle.kts
```

Ngoài ra `android/` được **pin về AGP 8.11.1 + Gradle 8.14.3** (template gốc là AGP 9.1.0 +
Gradle 9.3.1). Lý do: dưới Gradle 9, `flutter.groovy` còn thêm một lỗi nữa —
`groovy.xml.QName` không resolve được vì Gradle 9 không đưa các module Groovy vào compile
classpath — và AGP 8.11.1 đúng là version mà SDK plugin được compile với
(`compileOnly("com.android.tools.build:gradle:8.11.1")`). Bỏ pin này khi upstream sửa xong.

**macOS và Windows không bị ảnh hưởng** bởi cả hai thứ trên.

APK ra 52.9MB vì là universal (đủ mọi ABI). Muốn nhỏ hơn cho máy thật:

```bash
flutter build apk --release --split-per-abi   # ~20MB mỗi ABI
```

## Icon app

Icon của cả 3 nền tảng sinh từ **một bản vẽ duy nhất** trong
[`tools/gen-icons.py`](tools/gen-icons.py) (cần Pillow). Sửa màu/hình thì sửa
trong script rồi chạy lại — đừng chỉnh tay 20+ file PNG, lệch nhau ngay:

```bash
python3 tools/gen-icons.py
```

Nó ghi đè:

```
macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png   16→1024, lề + bóng kiểu Apple
windows/runner/resources/app_icon.ico                            .ico đa cỡ 16→256
android/app/src/main/res/mipmap-*/ic_launcher.png                icon legacy (máy trước API 26)
android/app/src/main/res/mipmap-*/ic_launcher_{fore,back}ground.png  layer cho adaptive icon
android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml        adaptive icon (Android 8+)
```

Hình vẽ: nền bo góc hổ phách (`accent` của `PaperColors`) + tờ note giấy kem gập
góc, 2 dòng kẻ và một dấu check — cùng ngôn ngữ hình với icon tray ở
`assets/tray/` để menu bar và Dock trông cùng một app.

Hai thứ dễ hiểu lầm khi kiểm tra:

- **`AppIcon.icns` trong bản build chỉ có 4 cỡ** (16, 32, 128, 256). Không phải
  thiếu icon: macOS đời mới đọc icon từ `Assets.car` (có đủ 10 rendition, tới
  512@2x), `.icns` chỉ là bản dự phòng cho hệ cũ. `actool` cố tình làm vậy —
  bản build với icon default của Flutter cũng ra đúng 4 cỡ đó.
- **Foreground của adaptive icon phải chừa safe zone** 66/108: launcher mỗi máy
  cắt theo mask riêng (tròn, squircle...), vẽ tràn viền là mất góc gập.

## Test

```bash
flutter test     # logic repo: add / done / restore / reorder / tombstone / merge
                 # so version + trạng thái kiểm cập nhật (không gọi mạng thật)
                 # popup xác nhận của mọi thao tác xoá
                 # bộ lọc ngày của History (mốc UTC → giờ địa phương) + "Xoá hết" khi đang lọc
                 # trạng thái mở-khi-khởi-động (channel macOS bị giả lập, không đụng OS)
```

`UpdateService` nhận `fetcher` để test không đi mạng — test widget nào dựng
`HomePage` cũng phải truyền fetcher giả, vì `HomePage` kiểm bản mới ngay khi mở.

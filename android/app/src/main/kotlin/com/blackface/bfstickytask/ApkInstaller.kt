package com.blackface.bfstickytask

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.widget.Toast
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Cài APK bản mới — phía native của `_AndroidInstaller` trong
 * `lib/data/update_installer.dart`.
 *
 * Dùng `PackageInstaller` (session API) chứ không dùng `ACTION_INSTALL_PACKAGE`
 * + FileProvider: đường kia deprecated, không có callback trạng thái, và không
 * có cách nào bỏ dialog xác nhận.
 *
 * Mức tự động, theo thứ tự tốt dần:
 *
 * 1. **Android 12+ và app đã là "installer of record"** của chính nó — tức là
 *    bản đang chạy được cài bởi app này ở lần cập nhật trước:
 *    `setRequireUserAction(USER_ACTION_NOT_REQUIRED)` + quyền
 *    `UPDATE_PACKAGES_WITHOUT_USER_ACTION` cho phép cài **im lặng, không dialog
 *    nào**. Đây là đường mong muốn.
 * 2. Không đủ điều kiện trên (bản đầu tiên cài bằng tay từ browser, hoặc
 *    Android 11 trở xuống): hệ thống tự hiện dialog "Cập nhật ứng dụng?" —
 *    user bấm 1 lần. Không bỏ được, và đây là giới hạn của Android chứ không
 *    phải thiếu sót ở đây.
 * 3. Chưa được cấp "cài ứng dụng không rõ nguồn": mở đúng trang cài đặt của
 *    app này. Chỉ phải bật **một lần**.
 *
 * Điều kiện tiên quyết cho cả ba: APK mới ký **cùng key** với bản đang cài,
 * không thì hệ thống từ chối (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`). Vì thế
 * release đã chuyển sang keystore cố định — xem `android/app/build.gradle.kts`.
 */
object ApkInstaller {
    /** Trùng với `_AndroidInstaller._channel` bên Dart. */
    const val CHANNEL = "bf_stickytask/apk_installer"

    /** Tên file trong session. Bất kỳ, chỉ để định danh trong session. */
    private const val ENTRY = "package.apk"

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "install" -> install(context, call.argument<String>("path"), result)
                else -> result.notImplemented()
            }
        }
    }

    private fun install(context: Context, path: String?, result: MethodChannel.Result) {
        if (path.isNullOrEmpty()) {
            result.error("bad_args", "Thiếu đường dẫn file APK.", null)
            return
        }
        val apk = File(path)
        if (!apk.isFile) {
            result.error("missing_file", "Không thấy file APK vừa tải.", null)
            return
        }

        // API 26+ bắt xin riêng quyền cài cho từng app. Chưa có thì mở đúng
        // trang cài đặt của app này rồi báo Dart để dialog nói user bật xong
        // bấm lại — không tự retry, vì user có thể bỏ ngang.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !context.packageManager.canRequestPackageInstalls()
        ) {
            openUnknownSourcesSettings(context)
            result.error(
                "permission_required",
                "Cần bật \"Cài ứng dụng không rõ nguồn\" cho BF-StickyTask. " +
                    "Bật xong quay lại bấm Cập nhật lần nữa — chỉ phải làm một lần.",
                null,
            )
            return
        }

        try {
            commitSession(context, apk)
            result.success(null)
        } catch (e: Exception) {
            result.error("install_failed", "Không cài được APK — ${e.message}", null)
        }
    }

    private fun commitSession(context: Context, apk: File) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL,
        ).apply {
            setAppPackageName(context.packageName)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Hệ thống tự bỏ qua yêu cầu này khi chưa đủ điều kiện (app
                // chưa phải installer of record) và hiện dialog như thường —
                // nên đặt vô điều kiện là an toàn, không cần tự kiểm.
                setRequireUserAction(
                    PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED,
                )
            }
        }

        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            session.openWrite(ENTRY, 0, apk.length()).use { out ->
                apk.inputStream().use { it.copyTo(out) }
                session.fsync(out)
            }

            // FLAG_MUTABLE là bắt buộc từ API 31: hệ thống phải nhét được
            // EXTRA_STATUS và EXTRA_INTENT vào intent này. Thiếu nó là
            // SecurityException ngay lúc commit.
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                flags = flags or PendingIntent.FLAG_MUTABLE
            }
            val pending = PendingIntent.getBroadcast(
                context,
                sessionId,
                Intent(context, InstallResultReceiver::class.java),
                flags,
            )
            session.commit(pending.intentSender)
        }
    }

    private fun openUnknownSourcesSettings(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            context.startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${context.packageName}"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        } catch (_: Exception) {
            // Một số ROM không có trang này. Thông báo lỗi bên Dart đã nói rõ
            // phải bật gì, user tự vào Settings được.
        }
    }
}

/**
 * Nhận kết quả từ `PackageInstaller`.
 *
 * Chạy được **sau khi app đã bị kill để thay APK** — receiver thuộc chính app
 * nên hệ thống cold-start nó lên để giao broadcast. Đó là lý do việc mở lại app
 * nằm ở đây chứ không nằm bên Dart: lúc STATUS_SUCCESS về thì code Dart cũ đã
 * chết từ lâu.
 */
class InstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE,
        )
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                // Đường số 2: hệ thống cần user xác nhận. Intent nó đưa phải
                // được start từ đây, không thì session treo mãi ở pending.
                @Suppress("DEPRECATION")
                val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                confirm?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                confirm?.let { runCatching { context.startActivity(it) } }
            }

            PackageInstaller.STATUS_SUCCESS -> relaunch(context)

            else -> {
                // Thất bại thì app đang chạy có thể đã chết, không còn dialog
                // Flutter nào để hiện lỗi — Toast là thứ duy nhất chắc chắn
                // tới được user.
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                Toast.makeText(
                    context,
                    "Cập nhật thất bại${if (message.isNullOrBlank()) "" else " — $message"}",
                    Toast.LENGTH_LONG,
                ).show()
            }
        }
    }

    /**
     * Mở lại app sau khi cài xong.
     *
     * **Best-effort.** Từ Android 10, app ở background bị chặn mở activity;
     * cài đặt vừa xong thường được miễn nhưng không có gì bảo đảm. Chặn thì
     * cùng lắm là user tự mở app — bản mới đã cài xong rồi.
     */
    private fun relaunch(context: Context) {
        val launch = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ?: return
        runCatching { context.startActivity(launch) }
    }
}

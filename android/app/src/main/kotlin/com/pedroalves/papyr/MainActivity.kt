package com.pedroalves.papyr

import android.content.ClipData
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.provider.MediaStore
import android.provider.MediaStore.MediaColumns
import android.provider.Settings
import android.util.Size
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileNotFoundException
import kotlin.math.max
import kotlin.math.roundToInt

/** Error with an explicit channel code (memory | not_found | decode | io). */
class Fail(val code: String, msg: String) : Exception(msg)

private object NotImplemented

class MainActivity : FlutterActivity() {
    private val imagesUri get() = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
    private val filesUri get() = MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        // Serial background queue: one call at a time, off the UI thread.
        MethodChannel(messenger, "papyr/native", StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue())
            .setMethodCallHandler { call, result ->
                try {
                    val out = handle(call)
                    if (out === NotImplemented) result.notImplemented() else result.success(out)
                } catch (e: Throwable) {
                    result.error(errorCode(e), e.toString(), null)
                }
            }
    }

    fun errorCode(e: Throwable): String = when (e) {
        is Fail -> e.code
        is OutOfMemoryError -> "memory"
        is FileNotFoundException, is SecurityException -> "not_found"
        is ImageDecoder.DecodeException -> "decode"
        else -> "io"
    }

    fun handle(call: MethodCall): Any? {
        fun str(k: String) = call.argument<String>(k)!!
        fun int(k: String) = (call.argument<Any>(k) as Number).toInt()
        fun uri() = Uri.parse(str("uri"))
        return when (call.method) {
            "cacheDir" -> cacheDir.path
            "preview" -> preview(str("path"), int("maxSide"))
            "save" -> save(str("path"), str("name"), str("mime"))
            "list" -> list()
            "delete" -> {
                if (contentResolver.delete(uri(), null, null) == 0) throw Fail("not_found", str("uri"))
                null
            }
            "read" -> contentResolver.openInputStream(uri())?.use { it.readBytes() } ?: throw FileNotFoundException(str("uri"))
            "thumbnail" -> {
                val size = int("size")
                jpeg(contentResolver.loadThumbnail(uri(), Size(size, size), null), 90)
            }
            "share" -> {
                share(call.argument<List<String>>("uris")!!.map(Uri::parse), str("mime"))
                null
            }
            "openAppSettings" -> {
                runOnUiThread {
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)))
                }
                null
            }
            "appVersion" -> packageManager.getPackageInfo(packageName, 0).versionName
            "cleanCache" -> {
                cacheDir.listFiles()?.forEach {
                    val n = it.name
                    if ((n.startsWith("CAP") && n.endsWith(".jpg")) || n.startsWith("papyr_")) it.delete()
                }
                null
            }
            else -> NotImplemented
        }
    }

    /** Compresses and recycles [b]. */
    private fun jpeg(b: Bitmap, quality: Int): ByteArray = try {
        ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.JPEG, quality, it) }.toByteArray()
    } finally {
        b.recycle()
    }

    /** ImageDecoder applies EXIF, so info.size is the upright full-resolution size. */
    private fun preview(path: String, maxSide: Int): Map<String, Any> {
        if (!File(path).exists()) throw FileNotFoundException(path)
        var w = 0
        var h = 0
        val b = ImageDecoder.decodeBitmap(ImageDecoder.createSource(File(path))) { d, info, _ ->
            w = info.size.width
            h = info.size.height
            val s = minOf(1f, maxSide.toFloat() / max(w, h))
            d.setTargetSize(max(1, (w * s).roundToInt()), max(1, (h * s).roundToInt()))
            d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        }
        return mapOf("bytes" to jpeg(b, 90), "width" to w, "height" to h)
    }

    private fun save(path: String, name: String, mime: String): Map<String, Any?> {
        val file = File(path)
        if (!file.exists()) throw FileNotFoundException(path)
        val pdf = mime == "application/pdf"
        val uri = contentResolver.insert(if (pdf) filesUri else imagesUri, ContentValues().apply {
            put(MediaColumns.DISPLAY_NAME, name)
            put(MediaColumns.MIME_TYPE, mime)
            put(MediaColumns.RELATIVE_PATH, if (pdf) "Documents/Papyr" else "Pictures/Papyr")
            put(MediaColumns.IS_PENDING, 1)
        }) ?: throw Fail("io", "insert failed")
        try {
            val out = contentResolver.openOutputStream(uri) ?: throw Fail("io", "no output stream")
            out.use { o -> file.inputStream().use { it.copyTo(o, 1 shl 16) } }
            contentResolver.update(uri, ContentValues().apply { put(MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (e: Throwable) {
            contentResolver.delete(uri, null, null)
            throw e
        }
        // MediaStore renames duplicates ("x (1).jpg"), so read the real name back.
        contentResolver.query(uri, arrayOf(MediaColumns.DISPLAY_NAME, MediaColumns.DATE_ADDED), null, null, null)!!.use { c ->
            if (!c.moveToFirst()) throw Fail("io", "saved row missing")
            return mapOf("uri" to uri.toString(), "name" to c.getString(0), "size" to file.length(), "date" to c.getLong(1) * 1000)
        }
    }

    private fun list(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            filesUri,
            arrayOf(MediaColumns._ID, MediaColumns.DISPLAY_NAME, MediaColumns.MIME_TYPE, MediaColumns.SIZE, MediaColumns.DATE_ADDED),
            "${MediaColumns.RELATIVE_PATH} IN (?, ?)",
            arrayOf("Pictures/Papyr/", "Documents/Papyr/"),
            "${MediaColumns.DATE_ADDED} DESC, ${MediaColumns._ID} DESC",
        )?.use { c ->
            while (c.moveToNext()) {
                val mime = c.getString(2) ?: continue
                val uri = ContentUris.withAppendedId(if (mime == "application/pdf") filesUri else imagesUri, c.getLong(0))
                out += mapOf("uri" to uri.toString(), "name" to c.getString(1), "mime" to mime, "size" to c.getLong(3), "date" to c.getLong(4) * 1000)
            }
        }
        return out
    }

    private fun share(uris: List<Uri>, mime: String) {
        val send = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris[0])
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
        }
        send.type = mime
        send.clipData = ClipData.newRawUri(null, uris[0]).apply { uris.drop(1).forEach { addItem(ClipData.Item(it)) } }
        send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        runOnUiThread { startActivity(Intent.createChooser(send, null)) }
    }
}

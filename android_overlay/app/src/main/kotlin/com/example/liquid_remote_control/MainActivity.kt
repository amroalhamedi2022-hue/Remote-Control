package com.example.liquid_remote_control

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors

// Experimental attended SAF receiver. Never requests all-files permission.
// SAF providers do NOT promise atomic publication; the temporary .part may
// be visible during copying. Fail closed if readback/rename is unsupported.
class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()
    private val sessions = mutableMapOf<String, Stage>() // worker thread only
    private var picker: MethodChannel.Result? = null
    private var approvedTree: Uri? = null
    private val pickerRequest = 42019
    private data class Stage(
        val file: File, val stream: FileOutputStream, val tree: Uri,
        val name: String, val size: Long, val digest: String, var written: Long = 0
    )

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        cacheDir.listFiles()?.filter {
            it.name.startsWith("liquidremote-inbound-") && it.name.endsWith(".part")
        }?.forEach { it.delete() }
        MethodChannel(engine.dartExecutor.binaryMessenger,
            "liquidremote/android_saf_receiver").setMethodCallHandler { call, result ->
            when (call.method) {
                "pickTree" -> {
                    if (picker != null) result.error("BUSY", "Picker already open", null)
                    else {
                        approvedTree = null
                        picker = result
                        try {
                            startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                            }, pickerRequest)
                        } catch (e: Exception) {
                            picker = null
                            result.error("PICKER", e.message, null)
                        }
                    }
                }
                "begin" -> {
                    val tree = approvedTree
                    approvedTree = null // one selection per transfer
                    if (tree == null || tree.toString() != call.argument<String>("tree")) {
                        result.error("DENIED", "No fresh SAF selection", null)
                    } else {
                        val name = call.argument<String>("name")
                        val bytes = call.argument<Number>("bytes")?.toLong()
                        val digest = call.argument<String>("sha256")
                        runWorker(result) {
                            require(name != null && bytes != null && digest != null)
                            begin(tree, name, bytes, digest)
                        }
                    }
                }
                "write" -> {
                    val id = call.argument<String>("id")
                    val bytes = call.argument<ByteArray>("data")
                    runWorker(result) {
                        val stage = sessions[id] ?: error("Unknown transfer")
                        require(bytes != null && bytes.isNotEmpty() && bytes.size <= 3072)
                        require(stage.written + bytes.size <= stage.size)
                        stage.stream.write(bytes)
                        stage.written += bytes.size
                        null
                    }
                }
                "commit" -> {
                    val id = call.argument<String>("id")
                    val name = call.argument<String>("name")
                    val bytes = call.argument<Number>("bytes")?.toLong()
                    val digest = call.argument<String>("sha256")
                    runWorker(result) {
                        val stage = sessions[id] ?: error("Unknown transfer")
                        require(stage.name == name && stage.size == bytes &&
                            stage.digest == digest && stage.written == stage.size)
                        try { publish(stage) }
                        finally {
                            sessions.remove(id)
                            try { stage.stream.close() } catch (_: Exception) {}
                            stage.file.delete()
                        }
                    }
                }
                "abort" -> {
                    val id = call.argument<String>("id")
                    runWorker(result) {
                        sessions.remove(id)?.let {
                            try { it.stream.close() } finally { it.file.delete() }
                        }
                        null
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun runWorker(result: MethodChannel.Result, action: () -> Any?) {
        worker.execute {
            try { result.success(action()) }
            catch (e: Exception) {
                result.error("SAF_RECEIVE", e.message ?: e.javaClass.simpleName, null)
            }
        }
    }

    private fun begin(tree: Uri, name: String, bytes: Long, digest: String): String {
        require(tree.scheme == "content" && DocumentsContract.isTreeUri(tree))
        require(name.isNotEmpty() && name.length <= 180 && name != "." && name != ".." &&
            !name.endsWith(".") && !name.endsWith(" ") &&
            name.none { it.code < 32 || it == '/' || it == '\\' || it == ':' ||
                it == '<' || it == '>' || it == '"' || it == '|' ||
                it == '?' || it == '*' })
        require(bytes in 0..(64L * 1024 * 1024))
        require(Regex("^[0-9a-f]{64}$").matches(digest))
        val file = File.createTempFile("liquidremote-inbound-", ".part", cacheDir)
        try {
            val id = UUID.randomUUID().toString()
            sessions[id] = Stage(file, FileOutputStream(file), tree, name, bytes, digest)
            return id
        } catch (e: Exception) { file.delete(); throw e }
    }

    private fun digest(file: File): String {
        val md = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                if (n > 0) md.update(buffer, 0, n)
            }
        }
        return md.digest().joinToString("") { "%02x".format(it) }
    }

    private fun publish(stage: Stage): String {
        stage.stream.flush()
        stage.stream.fd.sync()
        stage.stream.close()
        require(stage.file.length() == stage.size && digest(stage.file) == stage.digest) {
            "Private cache SHA-256 mismatch"
        }
        val root = DocumentsContract.buildDocumentUriUsingTree(
            stage.tree, DocumentsContract.getTreeDocumentId(stage.tree))
        val unique = UUID.randomUUID().toString()
        var temp: Uri? = null
        var published = false
        try {
            temp = DocumentsContract.createDocument(contentResolver, root,
                "application/octet-stream", ".liquidremote-" + unique + ".part")
                ?: error("SAF create unsupported")
            contentResolver.openOutputStream(temp, "wt")?.use { output ->
                stage.file.inputStream().use { it.copyTo(output, 65536) }
                output.flush()
            } ?: error("SAF write unsupported")
            val md = MessageDigest.getInstance("SHA-256")
            var read = 0L
            contentResolver.openInputStream(temp)?.use { input ->
                val buffer = ByteArray(65536)
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    if (n > 0) { read += n; md.update(buffer, 0, n) }
                }
            } ?: error("SAF readback unsupported")
            require(read == stage.size &&
                md.digest().joinToString("") { "%02x".format(it) } == stage.digest) {
                "SAF readback SHA-256 mismatch"
            }
            val finalUri = DocumentsContract.renameDocument(contentResolver, temp,
                "Received-" + unique + "-" + stage.name)
                ?: error("SAF rename unsupported")
            published = true
            return finalUri.toString()
        } finally {
            if (!published && temp != null) {
                try { DocumentsContract.deleteDocument(contentResolver, temp) }
                catch (_: Exception) { /* provider cleanup must be tested */ }
            }
        }
    }

    @Deprecated("Generated FlutterActivity uses activity result callbacks")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickerRequest) return
        val pending = picker ?: return
        picker = null
        val uri = if (resultCode == Activity.RESULT_OK) data?.data else null
        if (uri != null && data != null && DocumentsContract.isTreeUri(uri) &&
            (data.flags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION) != 0) {
            approvedTree = uri
            pending.success(uri.toString())
        } else {
            approvedTree = null
            pending.success(null)
        }
    }

    override fun onDestroy() {
        picker?.error("CANCELLED", "Receiver closed", null)
        picker = null
        approvedTree = null
        worker.execute {
            sessions.values.forEach {
                try { it.stream.close() } catch (_: Exception) {}
                it.file.delete()
            }
            sessions.clear()
        }
        worker.shutdown()
        super.onDestroy()
    }
}

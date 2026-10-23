package ai.mlc.mlcchat

import java.io.File
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Guards for data that arrives from a model repository (mlc-app-config.json,
 * mlc-chat-config.json, tensor-cache.json). Those files name the local files
 * the app writes, so a hostile or corrupted repository could otherwise use
 * "../" or absolute paths to overwrite other files in the app's storage.
 */
object SafeIO {
    private val SAFE_NAME = Regex("^[A-Za-z0-9._-]{1,255}$")

    /** Returns [dir]/[name] if [name] is a single plain path segment, else throws. */
    fun child(dir: File, name: String): File {
        require(SAFE_NAME.matches(name) && name != "." && name != "..") {
            "Rejected unsafe file name from model config: \"$name\""
        }
        val file = File(dir, name)
        require(file.canonicalFile.parentFile == dir.canonicalFile) {
            "Rejected path outside model directory: \"$name\""
        }
        return file
    }

    private const val CONNECT_TIMEOUT_MS = 15_000
    private const val READ_TIMEOUT_MS = 60_000

    /**
     * Opens [url] for download. HTTPS only (also enforced by the network
     * security config), bounded timeouts so a stalled CDN cannot hang a
     * download thread forever, and non-2xx responses become errors instead
     * of being saved as model files.
     */
    fun openHttps(url: URL): InputStream {
        require(url.protocol == "https") { "Refusing non-HTTPS download: $url" }
        val conn = url.openConnection() as HttpURLConnection
        conn.connectTimeout = CONNECT_TIMEOUT_MS
        conn.readTimeout = READ_TIMEOUT_MS
        conn.instanceFollowRedirects = true
        val code = conn.responseCode
        if (code !in 200..299) {
            conn.disconnect()
            throw IOException("HTTP $code for $url")
        }
        return conn.inputStream
    }
}

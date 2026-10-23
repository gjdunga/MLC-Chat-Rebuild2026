package ai.mlc.mlcchat

import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.core.content.FileProvider
import ai.mlc.mlcchat.ui.theme.MLCChatTheme
import java.io.File
import java.util.UUID

/**
 * No runtime permissions are requested anywhere in this activity:
 * - Gallery images come from the system Photo Picker, which hands back a
 *   read grant for the single item the user chose.
 * - Photos are taken by the system camera app (ACTION_IMAGE_CAPTURE) into a
 *   FileProvider URI in app-private cache; the camera app gets a one-shot
 *   write grant to that URI only. Declaring CAMERA would make that intent
 *   throw SecurityException until granted, so it is intentionally absent.
 */
class MainActivity : ComponentActivity() {
    var hasImage = false

    private val pickImageLauncher = registerForActivityResult(
        ActivityResultContracts.PickVisualMedia()
    ) { uri: Uri? ->
        uri?.let {
            Log.v("pickImageLauncher", "Selected image uri: $it")
            addImageMessage(it)
        }
    }

    private var cameraImageUri: Uri? = null
    private val takePictureLauncher = registerForActivityResult(
        ActivityResultContracts.TakePicture()
    ) { success: Boolean ->
        val uri = cameraImageUri
        if (success && uri != null) {
            Log.v("takePictureLauncher", "Camera image uri: $uri")
            addImageMessage(uri)
        }
    }

    lateinit var chatState: AppViewModel.ChatState

    @ExperimentalMaterial3Api
    override fun onCreate(savedInstanceState: Bundle?) {
        // targetSdk 35+ always draws edge to edge; opt in explicitly and pad
        // the content by the system bar / cutout / IME insets.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)

        chatState = AppViewModel(this.application).ChatState()

        setContent {
            Surface(
                modifier = Modifier
                    .fillMaxSize()
                    .windowInsetsPadding(WindowInsets.safeDrawing)
            ) {
                MLCChatTheme {
                    NavView(this)
                }
            }
        }
    }

    private fun addImageMessage(uri: Uri) {
        chatState.messages.add(
            MessageData(
                role = MessageRole.User,
                text = "",
                id = UUID.randomUUID(),
                imageUri = uri
            )
        )
    }

    fun pickImageFromGallery() {
        pickImageLauncher.launch(
            PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
        )
    }

    fun takePhoto() {
        val dir = File(cacheDir, "captures").apply { mkdirs() }
        // Keep only the latest capture; old ones are not referenced anymore.
        dir.listFiles()?.forEach { it.delete() }
        val file = File(dir, "IMG_${UUID.randomUUID()}.jpg")
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        cameraImageUri = uri
        takePictureLauncher.launch(uri)
    }
}

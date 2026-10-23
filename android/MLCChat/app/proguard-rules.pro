# Release builds run R8 (minify + resource shrinking).

# Gson reads/writes these via reflection (mlc-app-config.json,
# mlc-chat-config.json, tensor-cache.json). Keep field names and constructors.
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-keep class ai.mlc.mlcchat.AppConfig { *; }
-keep class ai.mlc.mlcchat.ModelRecord { *; }
-keep class ai.mlc.mlcchat.ModelConfig { *; }
-keep class ai.mlc.mlcchat.ParamsRecord { *; }
-keep class ai.mlc.mlcchat.ParamsConfig { *; }
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses

# JNI and engine classes are kept by mlc4j's consumer-rules.pro.

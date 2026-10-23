# TVM4J: Java classes looked up and called from libtvm4j_runtime_packed.so via JNI.
-keep class org.apache.tvm.** { *; }
# MLC engine API and its kotlinx-serialization protocol classes.
-keep class ai.mlc.mlcllm.** { *; }
-keepattributes *Annotation*, InnerClasses, Signature
-keepclassmembers class * {
    native <methods>;
}

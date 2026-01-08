# === ONNX Runtime 必须完整保留 ===
-keep class ai.onnxruntime.** { *; }

# JNI 相关（强烈建议）
-keepclasseswithmembers class * {
    native <methods>;
}

# 避免构造器被裁剪
-keepclassmembers class ai.onnxruntime.** {
    <init>(...);
}

# 防止方法签名被重写
-keepattributes Signature,InnerClasses,EnclosingMethod

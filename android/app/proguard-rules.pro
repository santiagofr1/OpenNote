# ML Kit (reconocimiento de letra del índice) instancia sus registradores por reflexión:
# sin esto R8 les borra el constructor y el plugin no se registra (MissingPluginException).
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_digital_ink.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google_mlkit_digital_ink_recognition.** { *; }
-keep class com.google_mlkit_commons.** { *; }

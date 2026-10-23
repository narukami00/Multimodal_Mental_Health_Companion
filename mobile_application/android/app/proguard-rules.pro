# Rules for the release build's code shrinker (R8) for the on-phone face reading.
#
# MediaPipe reads its protocol-buffer messages by FIELD NAME at run time (reflection). Without these rules the shrinker
# renames those fields ("Field platform_ for h2.B not found") and the face landmarker cannot even be created.
-keep class com.google.mediapipe.** { *; }
-keep class com.google.protobuf.** { *; }
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite { <fields>; }
-dontwarn com.google.mediapipe.**
-dontwarn com.google.protobuf.**

# MediaPipe's logging (Flogger) finds its caller by class name ("no caller found on the stack").
-keep class com.google.common.flogger.** { *; }
-dontwarn com.google.common.flogger.**

# ONNX Runtime's Java layer is called from native code by name.
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

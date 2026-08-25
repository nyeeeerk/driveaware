# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google ML Kit
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# Google Play Core (referenced by Flutter engine but not always present)
-dontwarn com.google.android.play.core.**

# Keep annotations
-keepattributes *Annotation*

# Keep Supabase / HTTP classes
-dontwarn okhttp3.**
-dontwarn okio.**

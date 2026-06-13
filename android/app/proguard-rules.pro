# Keep all Google ML Kit classes and methods to prevent minification/obfuscation failures
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_latin.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

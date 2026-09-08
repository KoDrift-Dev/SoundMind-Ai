# Flutter ProGuard Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Audio plugins & SQLite
-keep class com.ryanheise.** { *; }
-keep class com.tekartik.sqflite.** { *; }
-keep class com.yosemiteyss.flutter_volume_controller.** { *; }
-keep class com.csdcorp.speech_to_text.** { *; }
-keep class com.arthenica.ffmpegkit.** { *; }

# Prevent obfuscation of serializable / model classes
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    !private <fields>;
    !private <methods>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Don't warn about third party dependencies
-dontwarn javax.annotation.**
-dontwarn kotlin.**
-dontwarn com.google.android.play.core.**

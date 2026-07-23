# WorkManager + Room (MonitorWatchdog)
#
# AGP 9+ R8 full mode strips no-arg constructors on Room-generated classes
# (e.g. WorkDatabase_Impl) that WorkManager instantiates via reflection.
# Without these rules release builds crash in InitializationProvider at startup.

-keep class androidx.work.** { *; }
-keep class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keep class * extends androidx.work.Worker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}

-keep class * extends androidx.room.RoomDatabase {
    <init>();
    public ** createInvalidationTracker();
    public void clearAllTables();
}
-keep class androidx.room.RoomDatabase$JournalMode { *; }

-keep class com.anki.ankiblock.MonitorWatchdogWorker { *; }

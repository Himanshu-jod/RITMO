from pathlib import Path
import re

manifest = Path('android/app/src/main/AndroidManifest.xml')
if not manifest.exists():
    raise SystemExit('AndroidManifest.xml not found. Generate the Android platform first.')
text = manifest.read_text()

# Keep the user-facing Android launcher/app name in ALL CAPS.
application_match = re.search(r'<application\b[^>]*>', text)
if application_match:
    application_tag = application_match.group(0)
    if re.search(r'\bandroid:label\s*=', application_tag):
        updated_tag = re.sub(r'android:label=\"[^\"]*\"', 'android:label=\"RITMO\"', application_tag)
    else:
        updated_tag = application_tag[:-1] + ' android:label=\"RITMO\">'
    text = text.replace(application_tag, updated_tag, 1)
permissions = [
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.SCHEDULE_EXACT_ALARM',
    'android.permission.USE_FULL_SCREEN_INTENT',
    'android.permission.RECEIVE_BOOT_COMPLETED',
    'android.permission.VIBRATE',
]
for permission in permissions:
    tag = f'<uses-permission android:name="{permission}" />'
    if permission not in text:
        text = text.replace('<application', f'    {tag}\n    <application', 1)
receivers = '''
        <receiver
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"
            android:exported="false" />
        <receiver
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver"
            android:exported="false">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>
'''
if 'ScheduledNotificationReceiver' not in text:
    text = text.replace('</application>', receivers + '    </application>', 1)
# Let Android present the app over the lock screen when a full-screen alarm intent launches it.
activity_match = re.search(r'<activity\b[^>]*>', text)
if activity_match:
    activity_tag = activity_match.group(0)
    if 'android:showWhenLocked' not in activity_tag:
        updated = activity_tag[:-1] + ' android:showWhenLocked=\"true\" android:turnScreenOn=\"true\">'
        text = text.replace(activity_tag, updated, 1)
manifest.write_text(text)

# Ensure the generated FlutterActivity can appear over the lock screen for alarm launches.
kotlin = Path('android/app/src/main/kotlin/com/ritmo/ritmo/MainActivity.kt')
kotlin.parent.mkdir(parents=True, exist_ok=True)
kotlin.write_text('''package com.ritmo.ritmo

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setShowWhenLocked(true)
        setTurnScreenOn(true)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
''')
print('Android alarm permissions, notification receivers and MainActivity configured.')

# flutter_local_notifications scheduled notifications need core library desugaring.
gradle_kts = Path('android/app/build.gradle.kts')
gradle_groovy = Path('android/app/build.gradle')
if gradle_kts.exists():
    g = gradle_kts.read_text()
    if 'isCoreLibraryDesugaringEnabled = true' not in g:
        g = g.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
    if 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:' not in g:
        g = g.replace('dependencies {', 'dependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")', 1)
    gradle_kts.write_text(g)
elif gradle_groovy.exists():
    g = gradle_groovy.read_text()
    if 'coreLibraryDesugaringEnabled true' not in g:
        g = g.replace('compileOptions {', 'compileOptions {\n        coreLibraryDesugaringEnabled true', 1)
    if 'coreLibraryDesugaring ' not in g:
        g = g.replace('dependencies {', "dependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'", 1)
    gradle_groovy.write_text(g)

#!/bin/bash
# CityPulse one-shot setup. Run from inside this folder:  bash setup.sh
set -e
cd "$(dirname "$0")"

echo "==> Creating Flutter project shell"
mv lib lib_src
flutter create . --project-name citypulse --org com.citypulse --platforms android,ios,web
rm -rf lib test
mv lib_src lib

echo "==> Adding packages (latest compatible versions)"
flutter pub add firebase_core firebase_auth cloud_firestore image_picker geolocator flutter_map latlong2

echo "==> Android: permissions + minSdk 24"
perl -0pi -e 's/(<manifest[^>]*>)/$1\n    <uses-permission android:name="android.permission.INTERNET"\/>\n    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"\/>\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"\/>/' android/app/src/main/AndroidManifest.xml
for f in android/app/build.gradle.kts android/app/build.gradle; do
  [ -f "$f" ] && perl -pi -e 's/minSdk\s*=\s*flutter\.minSdkVersion/minSdk = 24/; s/minSdkVersion\s+flutter\.minSdkVersion/minSdkVersion 24/' "$f"
done

echo "==> iOS: permission texts"
PL=ios/Runner/Info.plist
/usr/libexec/PlistBuddy -c "Add :NSLocationWhenInUseUsageDescription string 'CityPulse uses your location to pin the reported problem.'" $PL 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSCameraUsageDescription string 'CityPulse uses the camera to photograph the problem.'" $PL 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :NSPhotoLibraryUsageDescription string 'CityPulse lets you attach a photo of the problem.'" $PL 2>/dev/null || true

echo "==> Connecting Firebase (pick or create your project when asked)"
dart pub global activate flutterfire_cli
export PATH="$PATH:$HOME/.pub-cache/bin"
flutterfire configure --platforms=android,ios,web

echo
echo "DONE. Now in the Firebase console:"
echo "  1. Authentication > Sign-in method > enable Email/Password"
echo "  2. Firestore Database > Create database, then paste firestore.rules into the Rules tab"
echo "Then run:  flutter run     (or: flutter run -d chrome)"

# CityPulse (Flutter + Firebase)

Real-time urban problem reporting for citizens, department officers and administrators.

## Run it
1. `flutter pub get`
2. `cp .env.example .env` and fill in a Gmail address and app password (used to email one-time codes).
3. Link your own Firebase project: `flutterfire configure --platforms=android,web`
   (or keep the included `lib/firebase_options.dart`).
4. Firebase console: enable Authentication > Email/Password, create Firestore,
   then `firebase deploy --only firestore:rules`.
5. Web: in one terminal `npm install nodemailer && node otp_server.js`, in another `flutter run -d chrome`.
   Android: `flutter run` (sends the code over SMTP directly, no relay needed).

## Workflow coverage
| Step | Implementation |
|---|---|
| Registration / login | Email + password, roles: citizen, officer, admin; emailed one-time code; forgot password |
| Report problem | Category, description, photo (camera or gallery), GPS pin |
| Interactive map | OpenStreetMap, pins coloured by status, tap for preview |
| Duplicate detection | Same category within 200 m offers "me too" instead of a new complaint |
| Prioritization | Category weight + urgent keywords + supporter count; deadline by priority |
| Department assignment | Automatic by category; admin can reassign to a department or officer |
| Officer updates | Start work, resolve with note and photo, reject |
| Notifications | Live in-app alerts plus status email |
| Tracking | Timeline on every complaint; citizen can rate the fix or reopen it |
| Admin dashboard | Statistics, filters, map, user and role management |
| Extras | Comments, search and category filter, top reporters, city pulse score |

## Known limits
- Alerts are in-app and by email; no push notification when the app is closed.
- Photos are stored compressed in Firestore, not Firebase Storage.
- Role is chosen at sign-up for demo convenience.
- The one-time code is generated and checked in the app, not on a server.

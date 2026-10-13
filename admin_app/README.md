# AFAKDECO PARK Admin App

Flutter/Dart admin client for the existing AFAKDECO PARK REST API.

## Current app features
- Telegram verification + JWT login
- Dashboard listing all vehicles, current drivers, and multiple status icons
- Reclamations / Accidents / Vidange filters, search, and date filter
- Reclamation detail sheet with comments, actions, media metadata, and Telegram archive links
- Vehicle history with all KM readings and Vidange summary
- Admin-confirmed Vidange value update with a before-save confirmation
- Driver cards and assignment/problem history
- Settings entry point and logout

## Cloud build (no Flutter installation needed on your PC)

GitHub Actions is configured in `.github/workflows/flutter-admin-build.yml`.

1. Open the repository on GitHub.
2. Select **Actions**.
3. Open **Flutter Admin App CI**.
4. Open the latest run and wait for **Build release APK** to finish.
5. Under **Artifacts**, download `afakdeco-admin-android-apk`.
6. Extract the ZIP; it contains `app-release.apk`.

The workflow runs automatically when files under `admin_app/` or the workflow itself change on `main`. It can also be started manually from the Actions page using **Run workflow**.

## Local development (optional)

From this directory:

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

## API and security

API base URL: `https://afakdeco-park-bot.onrender.com`

The Python Telegram bot and PostgreSQL backend remain the source of truth. The app does not contain the Telegram bot token or database credentials. Authentication uses the existing Telegram verification and backend JWT flow.

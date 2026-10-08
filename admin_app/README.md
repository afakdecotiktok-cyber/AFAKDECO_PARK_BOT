# AFAKDECO PARK Admin App

Flutter/Dart admin client for the existing AFAKDECO PARK REST API.

## Implemented
- Telegram verification + JWT login
- Dashboard with all vehicles and multi-status icons
- Reclamations / Accidents / Vidange filters
- Date and text search
- Vehicle history with Problems / Accidents / Vidange / KM
- Driver cards and assignment/problem history
- Settings shell and logout

## API
https://afakdeco-park-bot.onrender.com

The Python Telegram bot and PostgreSQL backend remain the source of truth. The Flutter app is an additional admin interface.

## Local setup
Run `flutter pub get` inside `admin_app`, then `flutter run`.

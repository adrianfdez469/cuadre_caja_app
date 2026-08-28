# Auth

`ApiClient` (Dio interceptor) attaches the Bearer token from `flutter_secure_storage` and transparently handles **401 → token refresh → retry** once. Token reads have a 5s timeout because `FlutterSecureStorage` can hang on some Android ABIs (notably arm64-v8a). Session restore + refresh happens in `SplashScreen._init()` on launch.

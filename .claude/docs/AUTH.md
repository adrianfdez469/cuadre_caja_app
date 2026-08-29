# Auth

`ApiClient` (Dio interceptor) attaches the Bearer token from `flutter_secure_storage` and transparently handles **401 → token refresh → retry** once. Token reads have a 5s timeout because `FlutterSecureStorage` can hang on some Android ABIs (notably arm64-v8a). Session restore + refresh happens in `SplashScreen._init()` on launch.

`SecureStorageService` keeps two separate credential entries, both cleared by `logout()` → `clearAll()`:
- `credentials` — saved on every successful login regardless of user choice; used only internally by `ApiClient.tryReLogin()` for silent background re-auth when a token refresh fails. Not related to the login screen.
- `rememberedCredentials` — saved only when the user checks "Recordarme" on `LoginScreen`; read on screen init to prefill the usuario/contraseña fields. Deleted when the box is unchecked at login time, or on any logout.

`LoginScreen` also wraps its fields in `AutofillGroup` with `AutofillHints.username`/`.password` so Android's own autofill/password manager can offer to fill and save credentials, independent of the app-managed "Recordarme" flow.

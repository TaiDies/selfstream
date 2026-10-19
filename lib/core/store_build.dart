/// True in the Microsoft Store package (built with --dart-define=STORE_BUILD=true).
/// The only difference from the sideloaded build: no self-update code (the Store updates the app).
/// Everything else is driven by what the connected server advertises, so a plain Navidrome shows a plain player.
const bool kStoreBuild = bool.fromEnvironment('STORE_BUILD');

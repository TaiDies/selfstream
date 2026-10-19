/// True in the Microsoft Store package (built with --dart-define=STORE_BUILD=true).
/// That build is a plain Subsonic / Navidrome music player: it never calls selfstream's own server extensions
/// (extra search sources, playlist following, discover pages, listening history, Discord card), whatever the
/// server it is pointed at offers.
const bool kStoreBuild = bool.fromEnvironment('STORE_BUILD');

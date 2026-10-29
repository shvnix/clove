# Clove patch

This local fork is based on `on_audio_query_plus_android` 1.3.0.

- Audio library access is checked with `READ_MEDIA_AUDIO` on Android 13+ and
  `READ_EXTERNAL_STORAGE` on older Android releases. Image and write-storage
  permissions are not needed to query or play local music.
- The missing-permission path returns immediately after completing its method
  channel result, preventing a second reply from the same query call.

`permission_handler` remains the only component that requests permissions at
runtime. Keep this fork until the upstream plugin has equivalent fixes.

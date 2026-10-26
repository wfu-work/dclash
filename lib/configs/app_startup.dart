/// Whether the application should connect the core after the first frame.
///
/// Preview builds never perform native or network mutations, even when the
/// setting is enabled. A profile is required because the core cannot start
/// without an active configuration.
bool shouldConnectOnLaunch({
  required bool preview,
  required bool autoStart,
  required bool hasActiveProfile,
}) => !preview && autoStart && hasActiveProfile;

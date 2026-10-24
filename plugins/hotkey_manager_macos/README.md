Based on hotkey_manager_macos 0.2.0 (MIT, see LICENSE).

This local adapter uses Carbon directly and returns registration errors through
the existing hotkey_manager channel. The upstream HotKey wrapper silently drops
registration failures. dclash needs an error to restore previous bindings when a
shortcut is occupied. Only system key-down actions are used by dclash.

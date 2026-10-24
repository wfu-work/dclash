Based on hotkey_manager_windows 0.2.0 (MIT, see LICENSE).

This local adapter checks native registration results and reports occupied or
unsupported shortcuts through the existing hotkey_manager channel. Failed
registrations are not saved, allowing dclash to restore previous bindings.
Unregister is idempotent so partial registration rollback is safe.

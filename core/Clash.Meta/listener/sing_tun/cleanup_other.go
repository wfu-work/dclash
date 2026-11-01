//go:build !windows

package sing_tun

func cleanupTunInterface(string) error { return nil }

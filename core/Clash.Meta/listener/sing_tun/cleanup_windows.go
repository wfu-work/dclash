//go:build windows

package sing_tun

import (
	"fmt"
	"os/exec"
	"strings"
	"syscall"
)

// sing-tun closes the Wintun handle but leaves the Windows routes and DNS
// servers it installed for AutoRoute. Remove everything belonging to the
// dedicated DClash adapter so a stopped or forcibly terminated Core cannot
// leave the host routing all traffic into a dead tunnel.
func cleanupTunInterface(name string) error {
	name = strings.TrimSpace(strings.Split(name, "(fd=")[0])
	if name == "" {
		return nil
	}
	escaped := strings.ReplaceAll(name, "'", "''")
	script := fmt.Sprintf(`
$ErrorActionPreference = 'SilentlyContinue'
$alias = '%s'
if ($null -ne (Get-NetAdapter -Name $alias -ErrorAction SilentlyContinue)) {
  $remaining = @()
  for ($attempt = 0; $attempt -lt 5; $attempt++) {
    foreach ($family in @('IPv4', 'IPv6')) {
      Get-NetRoute -InterfaceAlias $alias -AddressFamily $family -ErrorAction SilentlyContinue |
        Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue
      Get-NetIPAddress -InterfaceAlias $alias -AddressFamily $family -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    }
    $remaining = @(
      Get-NetRoute -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue
      Get-NetRoute -InterfaceAlias $alias -AddressFamily IPv6 -ErrorAction SilentlyContinue
      Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv4 -ErrorAction SilentlyContinue
      Get-NetIPAddress -InterfaceAlias $alias -AddressFamily IPv6 -ErrorAction SilentlyContinue
    )
    if ($remaining.Count -eq 0) { break }
    Start-Sleep -Milliseconds 100
  }
  Set-DnsClientServerAddress -InterfaceAlias $alias -ResetServerAddresses -ErrorAction SilentlyContinue
  Set-NetIPInterface -InterfaceAlias $alias -Forwarding Disabled -RouterDiscovery Disabled -ErrorAction SilentlyContinue
  if ($remaining.Count -gt 0) {
    throw "Windows TUN adapter $alias still has routes or addresses"
  }
}
`, escaped)
	command := exec.Command(
		"powershell.exe",
		"-NoProfile",
		"-NonInteractive",
		"-Command",
		script,
	)
	command.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	if output, err := command.CombinedOutput(); err != nil {
		return fmt.Errorf("cleanup TUN interface %q: %w: %s", name, err, strings.TrimSpace(string(output)))
	}
	return nil
}

package core

import (
	"os"
	"testing"

	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/constant"
)

// Selection tests exercise the real cache. Never open the user's cache.db.
func TestMain(m *testing.M) {
	home, err := os.MkdirTemp("", "dclash-core-test-")
	if err != nil {
		panic(err)
	}
	constant.SetHomeDir(home)
	cache := cachefile.Cache()
	code := m.Run()
	if cache.DB != nil {
		_ = cache.Close()
	}
	_ = os.RemoveAll(home)
	os.Exit(code)
}

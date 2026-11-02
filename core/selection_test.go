package core

import (
	"fmt"
	"strings"
	"testing"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
)

func selectionConfig(t *testing.T, members string) *config.Config {
	t.Helper()
	cfg, err := config.Parse([]byte(fmt.Sprintf(`
mode: rule
find-process-mode: off
profile: {store-selected: true}
proxies:
  - {name: Tokyo, type: direct}
  - {name: Seoul, type: direct}
proxy-groups:
  - {name: %s, type: select, proxies: [%s]}
rules: ["MATCH,DIRECT"]
`, t.Name(), members)))
	if err != nil {
		t.Fatalf("parse selection config: %v", err)
	}
	// The parser gives automatic groups a default health-check interval even
	// when interval is zero. Build real groups with disabled checks explicitly.
	var nodes []constant.Proxy
	for _, name := range strings.Split(members, ",") {
		nodes = append(nodes, cfg.Proxies[strings.TrimSpace(name)])
	}
	for _, suffix := range []string{"-auto", "-fallback"} {
		name := t.Name() + suffix
		health := provider.NewHealthCheck(nodes, "", 0, 0, true, nil)
		pd, err := provider.NewCompatibleProvider(name, nodes, health)
		if err != nil {
			t.Fatal(err)
		}
		option := outboundgroup.GroupCommonOption{Name: name}
		providers := []cp.ProxyProvider{pd}
		var group constant.ProxyAdapter
		if suffix == "-auto" {
			group, err = outboundgroup.NewURLTest(option, outboundgroup.URLTestOption{}, cfg.Proxies["DIRECT"], providers)
		} else {
			group, err = outboundgroup.NewFallback(option, outboundgroup.FallbackOption{}, cfg.Proxies["DIRECT"], providers)
		}
		if err != nil {
			t.Fatal(err)
		}
		cfg.Proxies[name] = adapter.NewProxy(group)
		cfg.Providers[name] = pd
	}
	return cfg
}

func TestApplyProxyConfigPreservesLatestSelection(t *testing.T) {
	withCurrentConfig(t, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })
	group := t.Name()
	applyProxyConfig(selectionConfig(t, "Tokyo, Seoul"), map[string]string{group: "Tokyo"})

	// A subscription reload carries an earlier host snapshot. The user changes
	// the live selection while the replacement config is being prepared.
	replacement := selectionConfig(t, "Tokyo, Seoul")
	result := handleChangeProxy(&ChangeProxyParams{GroupName: group, ProxyName: "Seoul"})
	if result.Message != "" {
		t.Fatal(result.Message)
	}
	applyProxyConfig(replacement, map[string]string{group: "Tokyo"})
	if got := groupNow(t, lookupProxy(group)); got != "Seoul" {
		t.Fatalf("selection after reload = %q, want the most recent choice Seoul", got)
	}
}

func TestApplyProxyConfigKeepsAutomaticGroupsAutomatic(t *testing.T) {
	withCurrentConfig(t, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })
	applyProxyConfig(selectionConfig(t, "Tokyo, Seoul"), nil)
	applyProxyConfig(selectionConfig(t, "Seoul, Tokyo"), nil)
	for _, suffix := range []string{"-auto", "-fallback"} {
		proxy := lookupProxy(t.Name() + suffix)
		if got := groupNow(t, proxy); got != "Seoul" {
			t.Errorf("%s selection = %q, want the automatic result Seoul", suffix, got)
		}
		view := proxyView(proxy).(map[string]any)
		if fixed, _ := view["fixed"].(string); fixed != "" {
			t.Errorf("%s pinned %q during reload without a manual selection", suffix, fixed)
		}
	}
}

func TestApplyProxyConfigPreservesAutomaticGroupOverridesAndResets(t *testing.T) {
	withCurrentConfig(t, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })
	applyProxyConfig(selectionConfig(t, "Tokyo, Seoul"), nil)
	for _, suffix := range []string{"-auto", "-fallback"} {
		group := t.Name() + suffix
		for _, pick := range []string{"Seoul", ""} {
			result := handleChangeProxy(&ChangeProxyParams{GroupName: group, ProxyName: pick})
			if result.Message != "" {
				t.Fatal(result.Message)
			}
			applyProxyConfig(selectionConfig(t, "Tokyo, Seoul"), map[string]string{group: "Tokyo"})
			view := proxyView(lookupProxy(group)).(map[string]any)
			if fixed, _ := view["fixed"].(string); fixed != pick {
				t.Fatalf("%s override after reload = %q, want %q", suffix, fixed, pick)
			}
		}
	}
}

func TestRestoredChoiceReplacesAnOlderCoreCache(t *testing.T) {
	withCurrentConfig(t, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })
	group := t.Name()
	cachefile.Cache().SetSelected(group, "Seoul")
	applyProxyConfig(selectionConfig(t, "Tokyo, Seoul"), map[string]string{group: "Tokyo"})
	applyProxyConfig(selectionConfig(t, "Tokyo, Seoul"), nil)
	if got := groupNow(t, lookupProxy(group)); got != "Tokyo" {
		t.Fatalf("selection = %q, want the restored profile choice Tokyo", got)
	}
}

func TestChangeProxyCachesOnlySuccessfulChoicesAndResets(t *testing.T) {
	group := t.Name()
	tunnel.UpdateProxies(map[string]constant.Proxy{group: selectorGroup(t, group, "Tokyo", "Seoul")}, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })

	result := handleChangeProxy(&ChangeProxyParams{GroupName: group, ProxyName: "Seoul"})
	if result.Message != "" {
		t.Fatal(result.Message)
	}
	if got := cachefile.Cache().SelectedMap()[group]; got != "Seoul" {
		t.Fatalf("cached selection = %q, want Seoul", got)
	}
	result = handleChangeProxy(&ChangeProxyParams{GroupName: group, ProxyName: "missing"})
	if result.Message == "" || cachefile.Cache().SelectedMap()[group] != "Seoul" {
		t.Fatalf("rejected selection changed cache: %+v", result)
	}
	result = handleChangeProxy(&ChangeProxyParams{GroupName: group})
	if cached, exists := cachefile.Cache().SelectedMap()[group]; result.Message != "" || !exists || cached != "" {
		t.Fatalf("selection reset was not cached: %+v, %q", result, cached)
	}
}

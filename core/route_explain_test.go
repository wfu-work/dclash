package core

import (
	"testing"

	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/rules"
	"github.com/metacubex/mihomo/tunnel"
)

func TestExplainRouteMatchesDomainRuleWithoutNetworkIO(t *testing.T) {
	group := selectorGroup(t, "Proxy", "Tokyo", "Seoul")
	rule, err := rules.ParseRule("DOMAIN-SUFFIX", "example.com", "Proxy", nil, nil)
	if err != nil {
		t.Fatalf("ParseRule: %v", err)
	}
	tunnel.UpdateProxies(map[string]constant.Proxy{
		"Proxy":  group,
		"DIRECT": namedProxy("DIRECT"),
	}, nil)
	tunnel.UpdateRules([]constant.Rule{rule}, nil, nil)
	previousMode := tunnel.Mode()
	tunnel.SetMode(tunnel.Rule)
	t.Cleanup(func() {
		tunnel.SetMode(previousMode)
		tunnel.UpdateProxies(nil, nil)
		tunnel.UpdateRules(nil, nil, nil)
	})
	stampRoute(7, 9)

	result, err := handleExplainRoute(&ExplainRouteParams{
		Url: "https://www.example.com/path?private=value#fragment",
	})
	if err != nil {
		t.Fatalf("handleExplainRoute: %v", err)
	}
	if result.Rule != "DomainSuffix" || result.RulePayload != "example.com" {
		t.Errorf("rule = %s(%s), want DomainSuffix(example.com)", result.Rule, result.RulePayload)
	}
	if result.Route != "Proxy" || result.Selected != "Tokyo" || result.Final != "Tokyo" {
		t.Errorf("route = %+v, want Proxy -> Tokyo", result)
	}
	if !result.Exact || result.NeedsDNS {
		t.Errorf("result exact=%v needsDNS=%v, want true false", result.Exact, result.NeedsDNS)
	}
	if result.CoreEpoch != 7 || result.PicksVersion != 9 {
		t.Errorf("stamp = %d/%d, want 7/9", result.CoreEpoch, result.PicksVersion)
	}
}

func TestExplainRouteDoesNotResolveIPRulesOrAcceptCredentials(t *testing.T) {
	ipRule, err := rules.ParseRule("IP-CIDR", "203.0.113.0/24", "Proxy", nil, nil)
	if err != nil {
		t.Fatalf("ParseRule: %v", err)
	}
	tunnel.UpdateProxies(map[string]constant.Proxy{
		"Proxy":  namedProxy("Proxy"),
		"DIRECT": namedProxy("DIRECT"),
	}, nil)
	tunnel.UpdateRules([]constant.Rule{ipRule}, nil, nil)
	previousMode := tunnel.Mode()
	tunnel.SetMode(tunnel.Rule)
	t.Cleanup(func() {
		tunnel.SetMode(previousMode)
		tunnel.UpdateProxies(nil, nil)
		tunnel.UpdateRules(nil, nil, nil)
	})

	result, err := handleExplainRoute(&ExplainRouteParams{Url: "https://example.com"})
	if err != nil {
		t.Fatalf("handleExplainRoute: %v", err)
	}
	if result.Route != "DIRECT" || !result.NeedsDNS || result.Exact {
		t.Errorf("result = %+v, want estimated DIRECT after skipped IP rule", result)
	}
	if _, err := handleExplainRoute(&ExplainRouteParams{Url: "https://user:secret@example.com"}); err == nil {
		t.Fatal("handleExplainRoute accepted URL credentials")
	}
}

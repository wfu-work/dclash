package core

import (
	"fmt"
	"net/url"
	"strconv"

	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
)

// handleExplainRoute inspects the applied rule set only. It must remain free
// of DNS lookups, HTTP requests, and proxy selection changes.
func handleExplainRoute(params *ExplainRouteParams) (*RouteExplanation, error) {
	parsed, err := url.ParseRequestURI(params.Url)
	if err != nil || parsed.Hostname() == "" ||
		(parsed.Scheme != "http" && parsed.Scheme != "https") ||
		parsed.User != nil {
		return nil, fmt.Errorf("invalid HTTP or HTTPS URL")
	}
	port := 80
	if parsed.Scheme == "https" {
		port = 443
	}
	if raw := parsed.Port(); raw != "" {
		port, err = strconv.Atoi(raw)
		if err != nil || port < 1 || port > 65535 {
			return nil, fmt.Errorf("invalid URL port")
		}
	}
	metadata := &constant.Metadata{
		NetWork: constant.TCP,
		Type:    constant.INNER,
		DNSMode: constant.DNSNormal,
		Host:    parsed.Hostname(),
		DstPort: uint16(port),
	}
	proxy, rule, needsDNS, exact := tunnel.ExplainRoute(metadata)
	if proxy == nil {
		return nil, fmt.Errorf("no route is available")
	}

	result := &RouteExplanation{
		Url:      parsed.String(),
		Host:     parsed.Hostname(),
		Port:     port,
		Route:    proxy.Name(),
		NeedsDNS: needsDNS,
		Exact:    exact,
	}
	if rule != nil {
		result.Rule = rule.RuleType().String()
		result.RulePayload = rule.Payload()
	}
	// Unwrap with touch=false so selectors, URL tests, and load balancers are
	// read without mutating their state or triggering a health check.
	seen := map[string]bool{proxy.Name(): true}
	current := proxy
	for {
		next := current.Unwrap(metadata, false)
		if next == nil || seen[next.Name()] {
			break
		}
		seen[next.Name()] = true
		if result.Selected == "" {
			result.Selected = next.Name()
		}
		result.Final = next.Name()
		current = next
	}
	if result.Final == "" {
		result.Final = result.Route
	}
	result.CoreEpoch, result.PicksVersion = routeStamp()
	return result, nil
}

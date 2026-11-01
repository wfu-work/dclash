package core

import (
	"sync"
	"time"

	"github.com/metacubex/mihomo/adapter"
	mihomoHttp "github.com/metacubex/mihomo/component/http"
	"github.com/metacubex/mihomo/component/proxydialer"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func init() {
	mihomoHttp.TLSConfigHook = relaxCertVerify
	adapter.UrlTestHook = func(url string, name string, delay uint16, timedOut bool) {
		sendMessage(DelayMessage, &Delay{Url: url, Name: name, Value: delayValue(delay, timedOut)})
	}
	statistic.DefaultRequestNotify = func(c statistic.Tracker) {
		notifyProbeRoute(c)
		if hasEventListener() {
			sendMessage(RequestMessage, c)
			watchRequestTraffic(c)
		}
	}
	dns.DefaultQueryNotify = func(record dns.QueryRecord) {
		if hasEventListener() {
			sendMessage(DnsMessage, newDnsQuery(record))
		}
	}
	executor.DefaultProviderLoadedHook = func(providerName string) {
		scheduleReclaimOwnership()
		scheduleLoadMemoryRelease()
		sendMessage(LoadedMessage, providerName)
	}
	updater.GeoUpdateHook = onGeoUpdate
	proxydialer.DefaultLoopNotify = reportDialerLoop
}

// Every dial through a looping dialer fails; one report stands for the burst.
const dialerLoopReportInterval = 3 * time.Second
const dialerLoopReportCacheSize = 1024

type dialerLoopReportCache struct {
	mu      sync.Mutex
	entries map[string]time.Time
}

func (cache *dialerLoopReportCache) shouldReport(
	proxyName string,
	now time.Time,
) bool {
	cache.mu.Lock()
	defer cache.mu.Unlock()

	if cache.entries == nil {
		cache.entries = make(map[string]time.Time)
	}
	for name, last := range cache.entries {
		if now.Sub(last) >= dialerLoopReportInterval {
			delete(cache.entries, name)
		}
	}
	if last, ok := cache.entries[proxyName]; ok && now.Sub(last) < dialerLoopReportInterval {
		return false
	}
	if len(cache.entries) >= dialerLoopReportCacheSize {
		var oldestName string
		var oldest time.Time
		for name, last := range cache.entries {
			if oldestName == "" || last.Before(oldest) {
				oldestName, oldest = name, last
			}
		}
		delete(cache.entries, oldestName)
	}
	cache.entries[proxyName] = now
	return true
}

var dialerLoopReports dialerLoopReportCache

func reportDialerLoop(proxyName string) {
	now := time.Now()
	if !dialerLoopReports.shouldReport(proxyName, now) {
		return
	}
	sendMessage(DialerLoopMessage, proxyName)
}

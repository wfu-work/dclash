package core

import (
	"fmt"
	"testing"
	"time"
)

func TestDialerLoopReportCacheDeduplicatesWithinInterval(t *testing.T) {
	cache := dialerLoopReportCache{}
	now := time.Unix(100, 0)

	if !cache.shouldReport("proxy", now) {
		t.Fatal("the first loop report was suppressed")
	}
	if cache.shouldReport("proxy", now.Add(dialerLoopReportInterval-time.Nanosecond)) {
		t.Fatal("a loop report inside the interval was not suppressed")
	}
	if !cache.shouldReport("proxy", now.Add(dialerLoopReportInterval)) {
		t.Fatal("a loop report after the interval was suppressed")
	}
}

func TestDialerLoopReportCacheHasBoundedCapacity(t *testing.T) {
	cache := dialerLoopReportCache{}
	now := time.Unix(200, 0)
	for i := 0; i < dialerLoopReportCacheSize+1; i++ {
		if !cache.shouldReport(fmt.Sprintf("proxy-%d", i), now) {
			t.Fatalf("initial report %d was suppressed", i)
		}
	}

	cache.mu.Lock()
	defer cache.mu.Unlock()
	if got := len(cache.entries); got != dialerLoopReportCacheSize {
		t.Fatalf("cache size = %d, want %d", got, dialerLoopReportCacheSize)
	}
}

func TestDialerLoopReportCacheExpiresEntries(t *testing.T) {
	cache := dialerLoopReportCache{}
	now := time.Unix(300, 0)
	cache.shouldReport("proxy", now)
	cache.shouldReport("other", now)

	if !cache.shouldReport("new", now.Add(dialerLoopReportInterval)) {
		t.Fatal("new report was suppressed after TTL cleanup")
	}
	cache.mu.Lock()
	defer cache.mu.Unlock()
	if len(cache.entries) != 1 {
		t.Fatalf("expired entries remain in cache: %d", len(cache.entries))
	}
}

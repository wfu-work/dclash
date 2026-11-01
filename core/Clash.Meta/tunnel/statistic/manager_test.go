package statistic

import (
	"sync"
	"testing"
)

func TestSnapshotMemoryReadIsSafeDuringUpdate(t *testing.T) {
	manager := &Manager{}
	const iterations = 100_000

	var group sync.WaitGroup
	group.Add(2)
	go func() {
		defer group.Done()
		for value := uint64(0); value < iterations; value++ {
			manager.memory.Store(value)
		}
	}()
	go func() {
		defer group.Done()
		for i := 0; i < iterations; i++ {
			_ = manager.Snapshot().Memory
		}
	}()
	group.Wait()
}

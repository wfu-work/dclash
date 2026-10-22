package core

import (
	"testing"
)

func TestValidateFiltersReadsEachBacktickPart(t *testing.T) {
	results := handleValidateFilters([]string{
		"",
		"(?i)港|(?<![a-z])hk(?![a-z])",
		"hk`jp",
		"[a-z-[aeiou]]",
		"(abc",
		"hk`(",
	})
	for i, valid := range []bool{true, true, true, true, false, false} {
		if (results[i] == "") != valid {
			t.Errorf("filter %d: got %q, want valid=%v", i, results[i], valid)
		}
	}
}

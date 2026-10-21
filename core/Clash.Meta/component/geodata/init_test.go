package geodata

import (
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestDownloadToPathDoesNotReplaceOnPartialResponse(t *testing.T) {
	directory := t.TempDir()
	path := filepath.Join(directory, "geoip.metadb")
	if err := os.WriteFile(path, []byte("previous database"), 0o644); err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Length", "1024")
		_, _ = io.WriteString(w, "partial")
	}))
	defer server.Close()

	if err := downloadToPath(server.URL, path); err == nil {
		t.Fatal("expected a truncated response to fail")
	}
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(content) != "previous database" {
		t.Fatalf("existing database was replaced: %q", content)
	}
	entries, err := os.ReadDir(directory)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Name() != filepath.Base(path) {
		t.Fatalf("temporary download was not cleaned up: %v", entries)
	}
}

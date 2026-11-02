package core

import (
	"sync"
	"time"

	"github.com/metacubex/mihomo/tunnel/statistic"
)

// mihomo announces a connection only as it opens, and has no hook for its
// close; the request list learns the traffic that follows from these reports.
const requestTrafficInterval = time.Second

// A full bulk queue drops a report; a closed request holds its connection only this many retries.
const requestTrafficCloseRetries = 5

type RequestTraffic struct {
	Id       string `json:"id"`
	Upload   int64  `json:"upload"`
	Download int64  `json:"download"`
}

type watchedRequest struct {
	tracker  statistic.Tracker
	upload   int64
	download int64
	// The tracker is announced before the manager stores it, so a request
	// missing from the manager on its first report may still be opening.
	fresh         bool
	closedReports int
}

type requestTrafficWatch struct {
	mu       sync.Mutex
	requests map[string]*watchedRequest
	running  bool
}

// requestTrafficSample is a stable view of a watched request used while the
// tracker and manager are queried outside requestTrafficWatch.mu. The pointer
// lets collect discard stale results if a request with the same id is replaced
// while those queries are in progress.
type requestTrafficSample struct {
	id            string
	request       *watchedRequest
	upload        int64
	download      int64
	fresh         bool
	closedReports int
}

type requestTrafficChange struct {
	sample  *requestTrafficSample
	traffic RequestTraffic
}

var requestTrafficSamplePool = sync.Pool{
	New: func() any {
		return make([]requestTrafficSample, 0, 64)
	},
}

var currentRequestTraffic = requestTrafficWatch{
	requests: map[string]*watchedRequest{},
}

func (w *requestTrafficWatch) add(tracker statistic.Tracker) (start bool) {
	info := tracker.Info()
	w.mu.Lock()
	defer w.mu.Unlock()
	w.requests[tracker.ID()] = &watchedRequest{
		tracker:  tracker,
		upload:   info.UploadTotal.Load(),
		download: info.DownloadTotal.Load(),
		fresh:    true,
	}
	start = !w.running
	w.running = true
	return start
}

func (w *requestTrafficWatch) collect(
	isOpen func(id string) bool,
	queue func([]RequestTraffic) (queued bool),
) (watching bool) {
	samples := requestTrafficSamplePool.Get().([]requestTrafficSample)
	samples = samples[:0]
	defer func() {
		// Samples retain tracker pointers. Clear them before pooling so a busy
		// watcher does not keep closed connections alive between collections.
		clear(samples)
		requestTrafficSamplePool.Put(samples[:0])
	}()

	w.mu.Lock()
	for id, request := range w.requests {
		samples = append(samples, requestTrafficSample{
			id:            id,
			request:       request,
			upload:        request.upload,
			download:      request.download,
			fresh:         request.fresh,
			closedReports: request.closedReports,
		})
	}
	w.mu.Unlock()

	var changed []requestTrafficChange
	for i := range samples {
		sample := &samples[i]
		if sample.closedReports > 0 || !sample.fresh && !isOpen(sample.id) {
			sample.closedReports++
		}
		info := sample.request.tracker.Info()
		upload, download := info.UploadTotal.Load(), info.DownloadTotal.Load()
		if upload != sample.upload || download != sample.download {
			changed = append(changed, requestTrafficChange{
				sample:  sample,
				traffic: RequestTraffic{Id: sample.id, Upload: upload, Download: download},
			})
		}
	}
	queued := len(changed) == 0
	if !queued {
		traffic := make([]RequestTraffic, len(changed))
		for i, change := range changed {
			traffic[i] = change.traffic
		}
		queued = queue(traffic)
	}

	w.mu.Lock()
	defer w.mu.Unlock()
	if queued {
		for _, change := range changed {
			request, ok := w.requests[change.sample.id]
			if !ok || request != change.sample.request {
				continue
			}
			request.upload = change.traffic.Upload
			request.download = change.traffic.Download
		}
	}
	for _, sample := range samples {
		request, ok := w.requests[sample.id]
		if !ok || request != sample.request {
			continue
		}
		request.fresh = false
		request.closedReports = sample.closedReports
		if sample.closedReports > 0 && (queued || sample.closedReports > requestTrafficCloseRetries) {
			delete(w.requests, sample.id)
		}
	}
	w.running = len(w.requests) > 0
	return w.running
}

func (w *requestTrafficWatch) clear() {
	w.mu.Lock()
	defer w.mu.Unlock()
	clear(w.requests)
	w.running = false
}

func watchRequestTraffic(tracker statistic.Tracker) {
	if currentRequestTraffic.add(tracker) {
		go runRequestTrafficWatch()
	}
}

func runRequestTrafficWatch() {
	ticker := time.NewTicker(requestTrafficInterval)
	defer ticker.Stop()
	for range ticker.C {
		if !hasEventListener() {
			currentRequestTraffic.clear()
			return
		}
		watching := currentRequestTraffic.collect(
			func(id string) bool {
				return statistic.DefaultManager.Get(id) != nil
			},
			func(changed []RequestTraffic) bool {
				return sendMessage(RequestTrafficMessage, changed)
			},
		)
		if !watching {
			return
		}
	}
}

// Command privacy-policy is a minimal static file server.
//
// It serves static HTML/CSS/assets from STATIC_DIR (default /data) and is
// designed to sit behind Traefik with the /privacy-policy prefix stripped,
// so the server itself only ever sees root-relative paths (e.g. "/",
// "/wedding-photos.html").
package main

import (
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

// noListFS wraps a http.FileSystem and returns 404 for directories that
// don't contain an index.html, preventing directory-listing disclosure.
type noListFS struct {
	fs http.FileSystem
}

func (nfs noListFS) Open(name string) (http.File, error) {
	f, err := nfs.fs.Open(name)
	if err != nil {
		return nil, err
	}

	stat, err := f.Stat()
	if err != nil {
		f.Close()
		return nil, err
	}

	if stat.IsDir() {
		index := strings.TrimSuffix(name, "/") + "/index.html"
		if idx, err := nfs.fs.Open(index); err != nil {
			f.Close()
			return nil, os.ErrNotExist
		} else {
			idx.Close()
		}
	}

	return f, nil
}

func withCommonHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("Referrer-Policy", "no-referrer-when-downgrade")
		next.ServeHTTP(w, r)
	})
}

func withLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start))
	})
}

func main() {
	dir := os.Getenv("STATIC_DIR")
	if dir == "" {
		dir = "/data"
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(noListFS{http.Dir(dir)}))
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           withLogging(withCommonHeaders(mux)),
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("privacy-policy server listening on :%s (serving %s)", port, dir)
	if err := srv.ListenAndServe(); err != nil {
		log.Fatal(err)
	}
}

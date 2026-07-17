// Command privacy-policy is a minimal static file server.
//
// Content is authored as Markdown (STATIC_DIR/*.md) and rendered to HTML on
// each request, so editing a policy is just editing a .md file - no build
// step. Any other static asset (css, images, ...) is served as-is.
//
// It is designed to sit behind Traefik with the /privacy-policy prefix
// stripped, so the server itself only ever sees root-relative paths (e.g.
// "/", "/wedding-photos.html").
package main

import (
	"bytes"
	"html/template"
	"log"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"

	"github.com/yuin/goldmark"
)

const pageTemplate = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>{{.Title}}</title>
<style>
  body { font-family: system-ui, sans-serif; max-width: 40rem; margin: 3rem auto; padding: 0 1rem; color: #222; line-height: 1.6; }
  a { color: #0a58ca; }
  code, pre { background: #f4f4f4; padding: .15rem .3rem; border-radius: 3px; }
</style>
</head>
<body>
{{.Content}}
</body>
</html>
`

var pageTmpl = template.Must(template.New("page").Parse(pageTemplate))

type pageData struct {
	Title   string
	Content template.HTML
}

// markdownHandler serves "/" and "/<name>.html" by rendering the matching
// "<name>.md" file from dir, falling back to a plain static file server
// (with directory listing disabled) for everything else.
func markdownHandler(dir string) http.Handler {
	assets := http.FileServer(noListFS{http.Dir(dir)})

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		clean := path.Clean(r.URL.Path)

		var mdName string
		switch {
		case clean == "/":
			mdName = "index.md"
		case strings.HasSuffix(clean, ".html"):
			mdName = strings.TrimSuffix(strings.TrimPrefix(clean, "/"), ".html") + ".md"
		default:
			assets.ServeHTTP(w, r)
			return
		}

		mdPath := filepath.Join(dir, filepath.FromSlash(mdName))
		if !isWithinDir(dir, mdPath) {
			http.NotFound(w, r)
			return
		}

		renderMarkdown(w, mdPath)
	})
}

func isWithinDir(dir, target string) bool {
	rel, err := filepath.Rel(filepath.Clean(dir), filepath.Clean(target))
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

func renderMarkdown(w http.ResponseWriter, mdPath string) {
	src, err := os.ReadFile(mdPath)
	if err != nil {
		http.NotFound(w, nil)
		return
	}

	var buf bytes.Buffer
	if err := goldmark.Convert(src, &buf); err != nil {
		http.Error(w, "failed to render page", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if err := pageTmpl.Execute(w, pageData{
		Title:   pageTitle(src, mdPath),
		Content: template.HTML(buf.String()), //nolint:gosec // content is authored locally, not user-supplied
	}); err != nil {
		log.Printf("template execute error: %v", err)
	}
}

// pageTitle uses the first "# Heading" in the markdown source, falling back
// to the filename.
func pageTitle(src []byte, mdPath string) string {
	for _, line := range strings.Split(string(src), "\n") {
		if t, ok := strings.CutPrefix(strings.TrimSpace(line), "# "); ok {
			return strings.TrimSpace(t)
		}
	}
	return strings.TrimSuffix(filepath.Base(mdPath), ".md")
}

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
	mux.Handle("/", markdownHandler(dir))
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

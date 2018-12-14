// factoriocalc runs the Factorio calculator using local game data.
//
// It mostly tries to work automatically, but see -help output for options.
package main

import (
	"flag"
	"fmt"
	"mime"
	"net"
	"net/http"
	"os"
	"path"

	"github.com/gobuffalo/packr"
	"github.com/skratchdot/open-golang/open"

	"github.com/KirkMcDonald/factorio-tools/factorioload"
)

var httpAddr = flag.String("http-addr", "localhost:8000", "Address on which to serve calculator.")
var verbose = flag.Bool("verbose", false, "Print more output.")
var startBrowser = flag.Bool("browser", true, "Whether to automatically launch web browser. (-browser=false to disable)")

func getOverride(version string) []byte {
	return []byte(fmt.Sprintf(`"use strict"
var OVERRIDE = "%s"
`, version))
}

type overrideHandler struct {
	overrides map[string][]byte
	handler   http.Handler
}

func (o *overrideHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	content := o.overrides[r.URL.Path]
	if content != nil {
		ctype := mime.TypeByExtension(path.Ext(r.URL.Path))
		w.Header().Set("Content-Type", ctype)
		_, err := w.Write(content)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
		}
		return
	}
	o.handler.ServeHTTP(w, r)
}

func main() {
	flag.Parse()

	loaderLibBox := packr.NewBox("../FactorioLoaderLib")
	processDataBox := packr.NewBox("../processdata")
	calcBox := packr.NewBox("../factorio-web-calc")

	data, err := factorioload.LoadData(processDataBox, loaderLibBox, *verbose)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	imagePath := "/images/sprite-sheet-" + data.SpriteHash + ".png"
	overrides := map[string][]byte{
		imagePath:                               data.SpriteSheet,
		"/data/local-" + data.Version + ".json": []byte(data.Normal),
		"/data/local-" + data.Version + "-expensive.json": []byte(data.Expensive),
		"/override.js": getOverride(data.Version),
	}

	url := "http://" + *httpAddr + "/calc.html"
	fmt.Fprintln(os.Stderr, "Starting server on", url)
	fmt.Fprintln(os.Stderr, "(Ctrl-C to exit.)")
	// Create the listener first, so the browser has something to connect to.
	listener, err := net.Listen("tcp", *httpAddr)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if *startBrowser {
		err = open.Start(url)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}
	handler := &overrideHandler{
		overrides: overrides,
		handler:   http.FileServer(calcBox),
	}
	http.Handle("/", handler)
	// Block forever.
	err = http.Serve(listener, nil)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

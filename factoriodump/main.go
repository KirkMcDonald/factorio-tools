// factoriodump dumps Factorio game data for the calculator.
//
// This is a tool for calculator development, and isn't intended for use
// by most users.
package main

import (
	"flag"
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"

	"github.com/gobuffalo/packr"

	"github.com/KirkMcDonald/factorio-tools/factorioload"
)

var calcDir = flag.String("calcdir", ".", "Calculator development directory.")
var force = flag.Bool("force", false, "Overwrite existing files.")
var prefix = flag.String("prefix", "vanilla", "Prefix to use for data files.")
var verbose = flag.Bool("verbose", false, "Print more output.")

func validCalcDir(path string) bool {
	p := filepath.Join(path, "calc.html")
	_, err := os.Stat(p)
	return err == nil
}

func checkPathExists(path, descr string) {
	_, err := os.Stat(path)
	if err == nil && !*force {
		fmt.Fprintf(os.Stderr, "%s \"%s\" already exists (use -force to overwrite).\n", descr, path)
		os.Exit(1)
	}
}

func main() {
	flag.Parse()

	if !validCalcDir(*calcDir) {
		fmt.Fprintf(os.Stderr, "Invalid calculator directory: %q\n", *calcDir)
		os.Exit(1)
	}

	loaderLibBox := packr.NewBox("../FactorioLoaderLib")
	processDataBox := packr.NewBox("../processdata")

	data, err := factorioload.LoadData(processDataBox, loaderLibBox, *verbose)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	spritePath := filepath.Join(*calcDir, "images", "sprite-sheet-"+data.SpriteHash+".png")
	checkPathExists(spritePath, "Sprite sheet")
	normalDataPath := filepath.Join(*calcDir, "data", fmt.Sprintf("%s-%s.json", *prefix, data.Version))
	checkPathExists(normalDataPath, "Data set")
	expensiveDataPath := filepath.Join(*calcDir, "data", fmt.Sprintf("%s-%s-expensive.json", *prefix, data.Version))
	checkPathExists(expensiveDataPath, "Data set")

	err = ioutil.WriteFile(spritePath, data.SpriteSheet, 0666)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	err = ioutil.WriteFile(normalDataPath, []byte(data.Normal), 0666)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	err = ioutil.WriteFile(expensiveDataPath, []byte(data.Expensive), 0666)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	fmt.Printf("Created files:\n  %s\n  %s\n  %s\n", spritePath, normalDataPath, expensiveDataPath)
}

package factorioload

import (
	"archive/zip"
	"bytes"
	"crypto/md5"
	"encoding/hex"
	"errors"
	"flag"
	"fmt"
	"image"
	"image/draw"
	"image/png"
	"io"
	"os"
	"path/filepath"
	"runtime"

	"github.com/KirkMcDonald/golua/lua"
	"github.com/gobuffalo/packr"
	"github.com/mitchellh/go-homedir"
)

var gameDir = flag.String("gamedir", "", "Factorio installation directory")
var dataDir = flag.String("datadir", "", "User data directory (e.g. ~/.factorio)")

const (
	pxWidth  = 32
	pxHeight = 32
)

var testFile = filepath.Join("data", "core", "info.json")

func validGameDir(path string) bool {
	p := filepath.Join(path, testFile)
	_, err := os.Stat(p)
	return err == nil
}

// Look in a bunch of places to try to find the game's directory.
// If -gamedir was provided, use that.
func findGameDir() (string, error) {
	if *gameDir != "" {
		if !validGameDir(*gameDir) {
			return "", errors.New("invalid game dir: " + *gameDir)
		}
		return *gameDir, nil
	}
	bin, err := os.Executable()
	if err != nil {
		return "", err
	}
	binDir := filepath.Dir(bin)
	testDirs := []string{
		filepath.Dir(binDir),
		binDir,
		".",
	}
	switch runtime.GOOS {
	case "windows":
		testDirs = append(testDirs,
			`C:\Program Files (x86)\Steam\steamapps\common\Factorio`,
			`C:\Program Files\Factorio`,
			// Where I've got it on my machine.
			`F:\Games\Steam\steamapps\common\Factorio`,
		)
	case "darwin":
		path, err := homedir.Expand(`~/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents`)
		if err == nil {
			testDirs = append(testDirs, path)
		}
		testDirs = append(testDirs, `/Applications/factorio.app/Contents`)
	default:  // linux, etc.
		path, err := homedir.Expand(`~/.steam/steam/SteamApps/common/Factorio`)
		if err == nil {
			testDirs = append(testDirs, path)
		}
		path, err = homedir.Expand(`~/.factorio`)
		if err == nil {
			testDirs = append(testDirs, path)
		}
	}
	for _, path := range testDirs {
		if validGameDir(path) {
			return path, nil
		}
	}
	return "", errors.New("Factorio game directory not found.")
}

func validDataDir(path string) bool {
	p := filepath.Join(path, "mods", "mod-list.json")
	_, err := os.Stat(p)
	return err == nil
}

func findDataDir() (string, error) {
	if *dataDir != "" {
		if !validDataDir(*dataDir) {
			return "", errors.New("invalid data dir: " + *dataDir)
		}
		return *dataDir, nil
	}
	bin, err := os.Executable()
	if err != nil {
		return "", err
	}
	binDir := filepath.Dir(bin)
	testDirs := []string{
		filepath.Dir(binDir),
		binDir,
		".",
	}
	var path string
	switch runtime.GOOS {
	case "windows":
		testDirs = append(testDirs, filepath.Join(os.Getenv("APPDATA"), "Factorio"))
	case "darwin":
		path, err = homedir.Expand("~/Library/Application Support/factorio")
		if err == nil {
			testDirs = append(testDirs, path)
		}
	default:
		path, err = homedir.Expand("~/.factorio")
		if err == nil {
			testDirs = append(testDirs, path)
		}
	}
	for _, path := range testDirs {
		if validDataDir(path) {
			return path, nil
		}
	}
	return "", errors.New("Factorio user data directory not found.")
}

type boxLoader struct {
	box packr.Box
}

func (b *boxLoader) search(L *lua.State) int {
	path := L.CheckString(1) + ".lua"
	fullpath := b.box.Path + "/" + path
	if !b.box.Has(path) {
		L.PushString("could not find " + fullpath)
		return 1
	}
	content := b.box.Bytes(path)
	status := L.LoadBuffer(content, fullpath)
	if status != 0 {
		fmt.Println("error loading " + fullpath)
		msg := L.ToString(-1)
		fmt.Println(msg)
		panic(status)
	}
	L.PushString(fullpath)
	return 2
}

func addSearcher(L *lua.State, box packr.Box) {
	loader := boxLoader{box}
	L.GetGlobal("table")
	L.GetField(-1, "insert")
	L.GetGlobal("package")
	L.GetField(-1, "searchers")
	L.Remove(-2)
	L.PushInteger(2)
	L.PushGoFunction(loader.search)
	err := L.Call(3, 0)
	if err != nil {
		panic(err)
	}
	L.Pop(1)
}

// Dumps table at top of stack to JSON. Leaves stack unchanged.
func getJSON(L *lua.State) string {
	table := L.GetTop()
	L.GetGlobal("JSON")
	L.GetField(-1, "encode")
	L.PushValue(-2)
	L.PushValue(table)
	L.PushNil()
	L.NewTable()
	L.PushBoolean(true)
	L.SetField(-2, "pretty")
	L.PushBoolean(false)
	L.SetField(-2, "align_keys")
	L.PushString("    ")
	L.SetField(-2, "indent")
	err := L.Call(4, 1)
	if err != nil {
		panic(err)
	}
	result := L.CheckString(-1)
	// Pop result and JSON module
	L.Pop(2)
	return result
}

type FactorioData struct {
	// The JSON-encoded datasets for the normal and the expensive recipe modes.
	Normal, Expensive string
	// A PNG-formatted image file containing the sprite sheet.
	SpriteSheet []byte
	// A hash of the sprite sheet, as stored in the datasets.
	SpriteHash string
	// Factorio version number
	Version string
}

func LoadData(processDataBox, loaderLibBox packr.Box, verbose bool) (FactorioData, error) {
	gameDir, err := findGameDir()
	if err != nil {
		return FactorioData{}, err
	}
	dataDir, err := findDataDir()
	if err != nil {
		return FactorioData{}, err
	}
	L := lua.NewState()
	L.OpenLibs()
	// The Lua bindings rename pcall/xpcall; change the names back.
	L.GetGlobal("unsafe_pcall")
	L.SetGlobal("pcall")
	L.GetGlobal("unsafe_xpcall")
	L.SetGlobal("xpcall")

	addSearcher(L, loaderLibBox)

	L.GetGlobal("require")
	L.PushString("library/factorioloader")
	err = L.Call(1, 1)
	if err != nil {
		return FactorioData{}, err
	}
	// Silence log output in non-verbose mode.
	if !verbose {
		err = L.DoString(`function log(s) end`)
		if err != nil {
			return FactorioData{}, err
		}
	}
	L.GetField(-1, "load_data")
	L.PushString(gameDir)
	modPath := filepath.Join(dataDir, "mods")
	L.PushString(modPath)
	err = L.Call(2, 0)
	if err != nil {
		return FactorioData{}, err
	}
	if verbose {
		fmt.Fprintln(os.Stderr, "data loaded")
	}

	addSearcher(L, processDataBox)
	L.GetGlobal("require")
	L.PushString("processdata")
	err = L.Call(1, 1)
	if err != nil {
		return FactorioData{}, err
	}
	L.GetField(-1, "process_data")
	L.GetGlobal("data")
	L.GetField(-1, "raw")
	L.Remove(-2)
	L.PushBoolean(verbose)
	err = L.Call(2, 1)
	if err != nil {
		return FactorioData{}, err
	}
	L.GetField(-1, "version")
	version := L.CheckString(-1)
	L.Pop(1)
	L.GetField(-1, "width")
	width := L.CheckInteger(-1)
	L.Pop(1)
	L.GetField(-1, "icons")
	L.Len(-1)
	length := L.CheckInteger(-1)
	L.Pop(1)

	height := length / width
	if length%width > 0 {
		height += 1
	}
	imageWidth := width * pxWidth
	imageHeight := height * pxHeight
	im := image.NewRGBA(image.Rect(0, 0, imageWidth, imageHeight))
	zipCache := map[string]map[string]*zip.File{}

	for i := 0; i < length; i++ {
		L.PushInteger(int64(i + 1))
		L.GetTable(-2)
		L.GetField(-1, "source")
		source := L.CheckString(-1)
		L.Pop(1)
		L.GetField(-1, "path")
		path := L.CheckString(-1)
		L.Pop(1)
		var iconFile io.ReadCloser
		if source == "file" {
			var err error
			iconFile, err = os.Open(path)
			if err != nil {
				return FactorioData{}, err
			}
		} else if source == "zip" {
			L.GetField(-1, "zipfile")
			zippath := L.CheckString(-1)
			L.Pop(1)
			files := zipCache[zippath]
			if files == nil {
				archive, err := zip.OpenReader(zippath)
				if err != nil {
					return FactorioData{}, err
				}
				defer func() {
					err := archive.Close()
					if err != nil {
						fmt.Fprintln(os.Stderr, err)
					}
				}()
				files = make(map[string]*zip.File)
				for _, file := range archive.File {
					files[file.Name] = file
				}
				zipCache[zippath] = files
			}
			var err error
			iconFile, err = files[path].Open()
			if err != nil {
				return FactorioData{}, err
			}
		}
		icon, _, err := image.Decode(iconFile)
		if err != nil {
			return FactorioData{}, err
		}
		err = iconFile.Close()
		if err != nil {
			return FactorioData{}, err
		}
		row := i / width
		col := i % width
		dest := image.Point{col * pxWidth, row * pxHeight}
		r := image.Rectangle{dest, dest.Add(image.Point{pxWidth, pxHeight})}
		draw.Draw(im, r, icon, image.ZP, draw.Src)
		// pop current icon
		L.Pop(1)
	}
	// pop icon array
	L.Pop(1)

	var outfile bytes.Buffer
	err = png.Encode(&outfile, im)
	if err != nil {
		return FactorioData{}, err
	}
	imgData := outfile.Bytes()
	hash := md5.New()
	// No need to check error.
	hash.Write(imgData)
	hexDigest := hex.EncodeToString(hash.Sum(nil))
	L.GetField(-1, "data")
	L.GetField(-1, "sprites")
	L.PushString(hexDigest)
	L.SetField(-2, "hash")
	L.Pop(1)
	// [..., return value, data]
	L.GetField(-2, "normal")
	// [..., return value, data, normal]
	L.SetField(-2, "recipes")
	// [..., return value, data w/ recipes]
	normalJSON := getJSON(L)
	L.GetField(-2, "expensive")
	L.SetField(-2, "recipes")
	expensiveJSON := getJSON(L)

	return FactorioData{
		Normal:      normalJSON,
		Expensive:   expensiveJSON,
		SpriteSheet: imgData,
		SpriteHash:  hexDigest,
		Version:     version,
	}, nil
}

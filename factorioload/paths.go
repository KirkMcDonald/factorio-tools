// +build !windows,!darwin

package factorioload

import (
	"github.com/mitchellh/go-homedir"
)

func getPaths() []string {
	var testDirs []string
	path, err := homedir.Expand(`~/.steam/steam/SteamApps/common/Factorio`)
	if err == nil {
		testDirs = append(testDirs, path)
	}
	path, err = homedir.Expand(`~/.factorio`)
	if err == nil {
		testDirs = append(testDirs, path)
	}
	return testDirs
}

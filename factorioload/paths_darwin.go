package factorioload

import (
	"github.com/mitchellh/go-homedir"
)

func getPaths() []string {
	var testDirs []string
	path, err := homedir.Expand(`~/Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents`)
	if err == nil {
		testDirs = append(testDirs, path)
	}
	testDirs = append(testDirs, `/Applications/factorio.app/Contents`)
	return testDirs
}

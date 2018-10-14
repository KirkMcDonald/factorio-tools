package factorioload

import (
	"path/filepath"

	"golang.org/x/sys/windows/registry"
)

func getPaths() []string {
	testDirs := []string{
		`C:\Program Files\Factorio`,
	}
	k, err := registry.OpenKey(registry.LOCAL_MACHINE, `SOFTWARE\Wow6432Node\Valve\Steam`, registry.QUERY_VALUE)
	if err != nil {
		return testDirs
	}
	defer k.Close()

	steamDir, _, err := k.GetStringValue("InstallPath")
	if err != nil {
		return testDirs
	}
	testDirs = append(testDirs, filepath.Join(steamDir, `steamapps\common\Factorio`))
	return testDirs
}

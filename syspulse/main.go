package main

import (
	"fmt"
	"os"
	"runtime"
	"strings"
)

const Version = "1.2.0"

func readProc(path string) string {
	data, err := os.ReadFile(path)
	if err != nil {
		return "n/a"
	}
	return strings.TrimSpace(string(data))
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "--version" {
		fmt.Println("syspulse", Version)
		return
	}
	fmt.Println("=== SysPulse ===")
	fmt.Println("version:   ", Version)
	fmt.Println("go:        ", runtime.Version())
	fmt.Println("cpus:      ", runtime.NumCPU())
	fmt.Println("goroutines:", runtime.NumGoroutine())
	fmt.Println("uptime:    ", readProc("/proc/uptime"))
	fmt.Println("loadavg:   ", readProc("/proc/loadavg"))
	fmt.Println("meminfo:   ", readProc("/proc/meminfo"))
}

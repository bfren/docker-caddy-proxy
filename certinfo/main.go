// certinfo prints details of the certificates in Caddy's storage directory as JSON, so they can be read by
// the proxy-certs helper (the image does not include openssl).
//
// Usage: certinfo <storage directory>
package main

import (
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"time"
)

type cert struct {
	Name      string    `json:"name"`
	Issuer    string    `json:"issuer"`
	CA        string    `json:"ca"`
	Names     []string  `json:"names"`
	NotBefore time.Time `json:"not_before"`
	NotAfter  time.Time `json:"not_after"`
	Path      string    `json:"path"`
}

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "usage: certinfo <storage directory>")
		os.Exit(2)
	}

	// Caddy stores certificates as certificates/<issuer>/<name>/<name>.crt
	paths, err := filepath.Glob(filepath.Join(os.Args[1], "certificates", "*", "*", "*.crt"))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	sort.Strings(paths)

	certs := []cert{}
	for _, path := range paths {
		c, err := read(path)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%s: %v\n", path, err)
			continue
		}
		certs = append(certs, c)
	}

	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	if err := enc.Encode(certs); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

// read parses the first (leaf) certificate in a PEM file
func read(path string) (cert, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return cert{}, err
	}

	block, _ := pem.Decode(data)
	if block == nil || block.Type != "CERTIFICATE" {
		return cert{}, fmt.Errorf("no PEM certificate found")
	}

	x, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return cert{}, err
	}

	issuer := x.Issuer.CommonName
	if len(x.Issuer.Organization) > 0 {
		issuer = x.Issuer.Organization[0] + " " + issuer
	}

	return cert{
		Name:      filepath.Base(filepath.Dir(path)),
		Issuer:    issuer,
		CA:        filepath.Base(filepath.Dir(filepath.Dir(path))),
		Names:     x.DNSNames,
		NotBefore: x.NotBefore.UTC(),
		NotAfter:  x.NotAfter.UTC(),
		Path:      path,
	}, nil
}

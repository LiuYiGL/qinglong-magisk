// qlextract extracts a gzip-compressed tar archive (including PAX extended
// headers, hard links and symbolic links) on Android. It exists because the
// toybox/busybox tar implementations truncate PAX linkpath records, which
// corrupts pnpm's hard-linked node_modules trees.
package main

import (
	"archive/tar"
	"bufio"
	"compress/gzip"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

type hardLink struct {
	name string
	link string
}

type dirMode struct {
	path string
	mode os.FileMode
}

func main() {
	if len(os.Args) < 3 {
		fmt.Fprintln(os.Stderr, "usage: qlextract <archive.tar.gz> <destdir>")
		os.Exit(2)
	}
	if err := run(os.Args[1], os.Args[2]); err != nil {
		fmt.Fprintln(os.Stderr, "qlextract:", err)
		os.Exit(1)
	}
}

func run(archive, dest string) error {
	f, err := os.Open(archive)
	if err != nil {
		return err
	}
	defer f.Close()

	br := bufio.NewReaderSize(f, 1<<20)
	magic, _ := br.Peek(2)
	var r io.Reader = br
	if len(magic) == 2 && magic[0] == 0x1f && magic[1] == 0x8b {
		gz, err := gzip.NewReader(br)
		if err != nil {
			return err
		}
		defer gz.Close()
		r = gz
	}

	if err := os.MkdirAll(dest, 0o755); err != nil {
		return err
	}
	dest, err = filepath.Abs(dest)
	if err != nil {
		return err
	}

	tr := tar.NewReader(r)
	var links []hardLink
	var dirs []dirMode
	var files, symlinks int64

	for {
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		name := filepath.Clean(strings.TrimPrefix(hdr.Name, "/"))
		if name == "." || name == "" {
			continue
		}
		if name == ".." || strings.HasPrefix(name, ".."+string(os.PathSeparator)) {
			continue
		}
		target := filepath.Join(dest, name)
		rel, err := filepath.Rel(dest, target)
		if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
			continue
		}
		mode := os.FileMode(hdr.Mode) & os.ModePerm
		if mode == 0 {
			mode = 0o644
		}

		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0o755); err != nil {
				return fmt.Errorf("mkdir %s: %w", name, err)
			}
			dirs = append(dirs, dirMode{target, mode})
		case tar.TypeReg, tar.TypeRegA:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return fmt.Errorf("mkdir parent %s: %w", name, err)
			}
			_ = os.Remove(target)
			out, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode)
			if err != nil {
				return fmt.Errorf("create %s: %w", name, err)
			}
			if _, err := io.Copy(out, tr); err != nil {
				out.Close()
				return fmt.Errorf("write %s: %w", name, err)
			}
			if err := out.Close(); err != nil {
				return fmt.Errorf("close %s: %w", name, err)
			}
			_ = os.Chmod(target, mode)
			_ = os.Chtimes(target, hdr.AccessTime, hdr.ModTime)
			chown(target, hdr)
			files++
		case tar.TypeSymlink:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return fmt.Errorf("mkdir parent %s: %w", name, err)
			}
			_ = os.Remove(target)
			if err := os.Symlink(hdr.Linkname, target); err != nil {
				return fmt.Errorf("symlink %s -> %s: %w", name, hdr.Linkname, err)
			}
			chown(target, hdr)
			symlinks++
		case tar.TypeLink:
			link := filepath.Clean(strings.TrimPrefix(hdr.Linkname, "/"))
			linkTarget := filepath.Join(dest, link)
			if rel, err := filepath.Rel(dest, linkTarget); err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
				continue
			}
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return fmt.Errorf("mkdir parent %s: %w", name, err)
			}
			_ = os.Remove(target)
			if err := os.Link(linkTarget, target); err != nil {
				links = append(links, hardLink{target, linkTarget})
			}
		}
	}

	// Hard links can refer to entries that appear later in the archive.
	for pass := 0; pass < 4 && len(links) > 0; pass++ {
		var pending []hardLink
		for _, l := range links {
			if err := os.Link(l.link, l.name); err != nil {
				pending = append(pending, l)
			}
		}
		if len(pending) == len(links) {
			break
		}
		links = pending
	}
	if len(links) > 0 {
		return fmt.Errorf("%d hard links could not be created (first: %s -> %s)", len(links), links[0].name, links[0].link)
	}

	for _, d := range dirs {
		_ = os.Chmod(d.path, d.mode)
	}
	fmt.Printf("qlextract: %d files, %d symlinks, %d dirs\n", files, symlinks, len(dirs))
	return nil
}

func chown(path string, hdr *tar.Header) {
	if hdr.Uid == 0 && hdr.Gid == 0 {
		return
	}
	if err := os.Lchown(path, hdr.Uid, hdr.Gid); err != nil && !errors.Is(err, syscall.EPERM) {
		// Ownership is cosmetic for a root-owned chroot; keep going.
	}
}

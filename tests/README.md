# TidaLuna regression tests

From the repository root:

```bash
bash -n cachy-freshinstall.sh
python3 -m unittest discover -s tests -v
```

Requires Python 3, Bash, and the standard Linux utilities (including
`unzip`) in `/usr/bin`. Tests isolate the TidaLuna section of the
provisioning script and mock `curl`, `sudo`, `mktemp`, and `unzip`.
ZIP validation and filesystem operations use real utilities in temporary
directories; no network, root access, package installation, or Tidal
installation is required.

The scenarios cover first installation, reinstalling an existing mod,
preserving an existing pristine backup, download failure, invalid/empty/
unexpected archives, extraction and staging failures, backup failures,
replacement failures, signals before and after publication, and retaining
recovery files if rollback fails.

These are regression checks for installation safety, not a live CachyOS
or Tidal launch test.

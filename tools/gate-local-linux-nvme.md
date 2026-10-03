# Gate checklist: local user → Linux → NVMe

Run after `./tools/rebuild-auth-image.sh --flash /dev/sdc` reports confirm PASS.

## USB

1. Boot USB. **Do not** enter Guest.
2. VT2 (`Ctrl+Alt+F2`), `root` / `test0000`:

```bash
ensure-software-tpm.sh
cryptohome --action=unmount
create-local-account.sh --force-remove --user localuser@localhost --password 'testpass'
verify-crostini-host.sh
```

3. Reboot → sign in as `localuser@localhost` on the **user pod**.
   Do **not** click Chrome “Create local account” → Next (powerwash).
4. Settings → Developers / Linux: must **not** be grayed out.
5. VT2 again:

```bash
lsblk -o NAME,SIZE,MODEL,TRAN,LABEL
install-to-disk.sh --dst /dev/<nvme> --dry-run
install-to-disk.sh --dst /dev/<nvme>
```

## NVMe

1. Boot from the installed disk.
2. Create local user again (USB vault did not transfer).
3. Sign in → confirm Linux still available.
4. `verify-auth-bringup.sh --phase nvme --user localuser@localhost --password 'testpass'`

# storage_btrfs migrations

One-time, per-host. Verified on artemis 2026-08-24.

`data/games` and `data/general/flatpak` are nested subvolumes of `data`. btrfs
snapshots are not recursive, so btrbk's `data` job records them as empty dirs.
That keeps game installs and wine prefixes out of the `48h 30d 2w 1m` retention;
`backup_btrbk` gives them their own hourly/24h jobs instead.

Nested subvolumes need no mount unit. `~/.var` keeps its existing bind mount:
a subvolume is an ordinary directory to the VFS.

A subvolume cannot be created over a populated directory, and the role fails
rather than skipping when it finds one. Hence this runbook.

`stat -c '%i' <path>` returns 256 for a subvolume root. That is the check.

Order matters: flatpak first, because the role's fail-task aborts phase2 before
it creates anything else.

---

## 1. Clear the flatpak path

```sh
flatpak ps
flatpak kill --all
sudo systemctl stop "home-$USER-.var.mount"
mountpoint ~/.var                     # must report NOT a mountpoint

mv ~/data/general/flatpak ~/data/general/flatpak.old
```

`mv` is a rename within one subvolume: instant, no copy.

## 2. Run phase2

```sh
just phase2
```

Creates both subvolumes, chowns them 0700, restarts the `~/.var` bind mount onto
the new (empty) flatpak subvolume, and deploys the `games` + `flatpak` btrbk jobs.

```sh
stat -c '%i' ~/data/games ~/data/general/flatpak    # both 256
findmnt ~/.var
systemctl list-timers 'btrbk-*'
```

> **Do not launch any flatpak between here and step 3.** `~/.var` is mounted on
> an empty subvolume; apps would initialize fresh profiles into it and you would
> be merging two divergent trees instead of copying one.

## 3. Restore the flatpak data

```sh
cp -a --reflink=always ~/data/general/flatpak.old/. ~/data/general/flatpak/
```

Same filesystem, so `--reflink=always` shares extents: near-instant, no extra
space. It errors rather than falling back, so a silent slow copy cannot happen.

`~/.var` is already mounted on the destination, so the data appears there
immediately. Verify, then reclaim:

```sh
diff -rq ~/data/general/flatpak.old ~/data/general/flatpak
flatpak list | head
rm -rf ~/data/general/flatpak.old
```

`diff -rq` reads 131G twice and is slow; `du -sb` on both plus a file count is a
reasonable substitute.

> `df` will not drop afterwards. Existing btrbk snapshots of `data` still hold
> the old directory until they age out of `48h 30d 2w 1m` — up to a month.
> Expected, not a failed migration.

## 4. XIVLauncher and ~/Games

`~/Games` is symlinked on every host (guarded on the games subvolume existing).
`~/.xlcore` only where chezmoi `has_gaming` is set.

> **Check `~/Games` first.** If it exists as a real directory, `L+` will rm -rf
> it on apply. On artemis it held a 660M umu prefix. Move it in before applying:
>
> ```sh
> ls -A ~/Games && du -sh ~/Games
> ```

Both copies cross the filesystem boundary (`~` on the root LUKS volume, `~/data`
on the data one), so these are real copies, not reflinks.

```sh
pkill -f XIVLauncher.Core
pgrep -af 'umu|lutris|wine' || echo clear

cp -a ~/Games/. ~/data/games/

# has_gaming hosts only
mkdir -p ~/data/games/xlcore
cp -a ~/.xlcore/. ~/data/games/xlcore/

diff -rq ~/Games ~/data/games
diff -rq ~/.xlcore ~/data/games/xlcore
rm -rf ~/Games ~/.xlcore
```

Delete before `chezmoi apply`, not after: `L+` would rm -rf them anyway, but this
way you delete a verified copy rather than trusting tmpfiles with the only one.

## 5. chezmoi

```sh
chezmoi apply ~/.config/user-tmpfiles.d/13-games.conf
systemd-tmpfiles --user --create
readlink ~/Games ~/.xlcore
```

A targeted apply does not fire the `run_onchange` tmpfiles script, hence the
manual `systemd-tmpfiles` line. Use plain `chezmoi apply` to take everything.

`13-games.conf` is guarded on `~/data/games` existing rather than on
`data/.ready`, for two reasons: no dangling `~/Games` before the role has run,
and tmpfiles must never create `~/data/games` itself — a plain directory there
would fail the role's inode-256 check on the next phase2.

`~/Games` points at the subvolume root, so `umu` sits beside `xlcore`.

XIVLauncher hardcodes `$HOME/.xlcore` upstream (goatcorp/FFXIVQuickLauncher#1029
is open; `XL_USERDIR` exists only in rankynbass' fork), so that symlink is not
optional. `launcher.ini` stores absolute paths but resolves through it unchanged.
The flatpak holds `filesystems=home` and `~/data` is under `$HOME`, so no
`flatpak override` is needed.

## 6. Verify the snapshot jobs

The timers fire hourly on their own. Confirm the first run succeeded rather than
just ran:

```sh
systemctl list-timers 'btrbk-*'
systemctl show btrbk-games.service btrbk-flatpak.service -p Result -p ExecMainStatus
journalctl -u btrbk-games.service -u btrbk-flatpak.service --since '-1h'
```

Expect `Result=success` / `ExecMainStatus=0` and a `+++` line per job:

```
+++ /mnt/btrfs_data/snapshots/<host>.flatpak.<ts>
+++ /mnt/btrfs_data/snapshots/<host>.games.<ts>
```

To force a run instead of waiting: `sudo systemctl start btrbk-games.service`.
Add `-n` to a manual `btrbk -c ... run` for a dry run.

Install games only after this point, so the data lands inside the subvolume.

---

## Per-host notes

- **artemis** (2026-08-24): complete, all 6 steps verified.
  flatpak 131G, xlcore 693M, ~/Games 659M (umu). Both btrbk jobs green.
- **apollo**: all steps. Step 4 is `~/Games` only (no `has_gaming`).
- **hephaestus**: all steps. Step 4 is `~/Games` only (no `has_gaming`).

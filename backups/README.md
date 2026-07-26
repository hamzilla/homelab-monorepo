# B2 Photo Backup

Encrypted nightly backup of Synology photos to Backblaze B2, with an interactive restore shell for browsing and downloading.

## Features

**Backup**
- Nightly sync at midnight via Synology Task Scheduler
- Client-side encryption (rclone crypt) — filenames and contents encrypted before upload
- Syncs two photo directories: `hamzilla/Photos/` and `salwabalwa/Photos/`
- Excludes `.DS_Store`, `Thumbs.db`, `._*`, `.AppleDouble`
- Logs to `/var/log/hamzilla-services/b2-photo-backup.log`

**Restore**
- Interactive filesystem shell — navigate encrypted backups like a local directory
- `ls`, `cd`, `pwd`, `tree`, `du` to browse what's in the bucket
- `get <file>` to download a single file
- `get <folder>` to download an entire folder
- `get .` or `getall` to download everything in current directory
- `download-all` to restore everything
- `find <pattern>` to search for files by name
- Files restored to `./restored/` (configurable)

## Quick Start

```bash
# Clone on Synology
cd /volume1/homes/hamzilla
git clone git@github.com:hamzilla/homelab-monorepo.git
cd homelab-monorepo/backups/b2-photos

# One-time setup
./setup.sh

# Run backup manually
./backup.sh

# Restore files
./restore.sh
```

## Setup

### Prerequisites
- Synology NAS with SSH access
- Backblaze B2 account with an app key

### Credentials

Backblaze credentials are in **1Password** (UUID: `4gy3y7zex57wcftxkjrtnazqoy`).

On the Synology, create `~/.config/.env`:
```bash
BACKBLAZE_KEY_ID=your_key_id
BACKBLAZE_APP_KEY=your_app_key
```

### Install

```bash
cd /volume1/homes/hamzilla/homelab-monorepo/backups/b2-photos
./setup.sh
```

`setup.sh` will:
1. Install rclone if not present
2. Configure the `b2` remote (Backblaze backend)
3. Configure the `b2crypt` remote (client-side encryption)
4. Prompt you to set an encryption password (stored in rclone config)

### Schedule (Synology Task Scheduler)

1. DSM → Control Panel → Task Scheduler
2. Create → Scheduled Task → User-defined script
3. Name: `B2 Photo Backup`, User: `root`
4. Schedule: Daily at 00:00
5. Run command:
   ```bash
   /volume1/homes/hamzilla/homelab-monorepo/backups/b2-photos/backup.sh
   ```

## Backup

```bash
./backup.sh
```

Syncs both photo directories to B2 with encryption. Run manually or via Task Scheduler.

| Source (Synology) | Destination (B2, encrypted) |
|---|---|
| `/volume1/homes/hamzilla/Photos/` | `b2crypt:hamzilla-photos/` |
| `/volume1/homes/salwabalwa/Photos/` | `b2crypt:salwabalwa-photos/` |

## Restore

```bash
./restore.sh
```

Opens an interactive shell where you can browse and download files:

```
B2 Photo Restore Shell
────────────────────────────────────────────
Quick start:
  ls            See what's in the bucket
  cd <folder>   Navigate into a folder
  get <name>    Download a file or folder
  get .         Download everything in current dir
  download-all  Download everything from root

b2crypt:/ $ ls
  hamzilla-photos/            1200 items
  salwabalwa-photos/          41764 items

b2crypt:/ $ cd salwabalwa-photos/Photography
b2crypt:/salwabalwa-photos/Photography $ ls
  2020/                       500 items
  2021/                       300 items

b2crypt:/salwabalwa-photos/Photography $ get 2020
[INFO] Downloading ... -> ./restored/salwabalwa-photos/Photography/2020/
```

### One-shot Commands

```bash
./restore.sh list                           # see top-level folders
./restore.sh browse hamzilla-photos         # show folder contents
./restore.sh search ".jpg"                  # find files by name
./restore.sh download-all                   # download everything
./restore.sh download-folder hamzilla-photos/2024
./restore.sh download-file hamzilla-photos/2024/vacation/photo.jpg
```

## Architecture

| Component | Purpose |
|---|---|
| `setup.sh` | One-time install and config |
| `backup.sh` | Nightly encrypted sync |
| `restore.sh` | Interactive browse/download shell |
| `rclone.conf.template` | Config template (no secrets) |

rclone remotes:

| Remote | Type | Purpose |
|---|---|---|
| `b2` | b2 | Backblaze B2 backend |
| `b2crypt` | crypt | Client-side encryption over `b2:hamzilla-backups` |

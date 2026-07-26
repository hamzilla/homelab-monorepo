# Backups

## B2 Photo Backup

Nightly encrypted backup of Synology photos to Backblaze B2.

### Directories Backed Up

| Source (Synology) | Destination (B2, encrypted) |
|---|---|
| `/volume1/homes/hamzilla/Photos/` | `b2crypt:hamzilla-photos/` |
| `/volume1/homes/salwabalwa/Photos/` | `b2crypt:salwabalwa-photos/` |

### Credentials

Backblaze credentials are stored in **1Password**:
- Item UUID: `4gy3y7zex57wcftxkjrtnazqoy`
- Local env file: `~/.config/.env` (on Synology)

### Setup (one-time)

1. Clone this repo on the Synology:
   ```bash
   cd /volume1/homes/hamzilla
   git clone <repo-url> homelab-monorepo
   cd homelab-monorepo/backups/b2-photos
   ```
2. Run `./setup.sh` — it will install rclone if needed, configure the B2 remote, and prompt for an encryption password
   ```bash
   ./setup.sh
   ```

### Nightly Backup

`backup.sh` syncs both photo directories to B2 with client-side encryption.

- **Schedule:** Midnight (Synology Task Scheduler)
- **Log:** `/var/log/b2-photo-backup.log`
- **Excludes:** `.DS_Store`, `Thumbs.db`, `._*`, `.AppleDouble`

To run manually:

```bash
./backup.sh
```

### Restore

`restore.sh` provides an interactive tool to browse and download files from B2.

```bash
# Interactive menu
./restore.sh

# List top-level folders
./restore.sh list

# Browse a folder
./restore.sh browse hamzilla-photos

# Search for files
./restore.sh search ".jpg"

# Download a specific folder
./restore.sh download-folder hamzilla-photos/2024

# Download a single file
./restore.sh download-file hamzilla-photos/2024/vacation/photo1.jpg

# Download everything
./restore.sh download-all
```

Files are restored to `./restored/` by default (configurable in interactive mode).

### Synology Task Scheduler Setup

1. Open DSM → Control Panel → Task Scheduler
2. Create → Scheduled Task → User-defined script
3. General: Name = `B2 Photo Backup`, User = `root`
4. Schedule: Daily at 00:00
5. Task Settings → Run command:
   ```bash
   /volume1/homes/hamzilla/homelab-monorepo/backups/b2-photos/backup.sh
   ```
6. Click OK

### rclone Config

Config location: `~/.config/rclone/rclone.conf`

Two remotes are configured:

| Remote | Type | Purpose |
|---|---|---|
| `b2` | b2 | Backblaze B2 backend |
| `b2crypt` | crypt | Client-side encryption wrapping `b2:hamzilla-backups` |

A template is provided in `rclone.conf.template` (no secrets).

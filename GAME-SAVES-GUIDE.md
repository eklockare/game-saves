# Game Saves Management Guide

This guide explains how to centralize and version control your game saves using Git and symlinks.

## Overview

The `manage-game-saves.sh` script helps you:
- **Centralize** all game saves from various locations into one directory
- **Version control** your saves with Git (track changes, restore old saves)
- **Automatically backup** saves using symlinks (games write to symlinks that point to your Git repo)

**Note on Stow vs. Direct Symlinks:**
This script uses a "reverse stow" approach. Traditional GNU Stow symlinks *from* a managed directory *to* scattered locations. We do the opposite - symlink *from* scattered game save locations *to* a centralized git repo. This makes the repo the single source of truth, which is better for version control. While you could use `stow` for managing the repo structure internally, the primary linking must be done manually since stow doesn't support this reverse direction.

## Quick Start

### 1. Initialize the Repository

```bash
cd ~/game-saves
./manage-game-saves.sh init
```

This creates a Git repository in `~/game-saves` if it doesn't exist.

### 2. Discover Your Game Saves

```bash
./manage-game-saves.sh discover
```

This scans common locations for game saves:
- Steam (Proton) games: `~/.local/share/Steam/steamapps/compatdata/*/pfx/`
- Heroic Launcher games: `~/.var/app/com.heroicgameslauncher.hgl/`
- Native Linux games: `~/.local/share/`

### 3. Link Game Saves

Once you've found a game save location, link it to your repository:

```bash
./manage-game-saves.sh link <source_path> <game_name>
```

**Examples:**

```bash
# Alan Wake 2 (Epic via Heroic)
./manage-game-saves.sh link ~/.var/app/com.heroicgameslauncher.hgl/config/Epic/Saved/remedy-alan-wake-2 alan-wake-2

# Baldur's Gate 3 (Steam)
./manage-game-saves.sh link ~/.local/share/Steam/steamapps/compatdata/1086940/pfx/drive_c/users/steamuser/AppData/Local/Larian\ Studios/Baldur\'s\ Gate\ 3 baldurs-gate-3

# Clair Obscur (Steam) - find the app ID first with discover
./manage-game-saves.sh link ~/.local/share/Steam/steamapps/compatdata/APPID/pfx/drive_c/users/steamuser/Saved\ Games/ClairObscur clair-obscur

# Kingdom Come Deliverance 2
./manage-game-saves.sh link ~/.local/share/Steam/steamapps/compatdata/1771300/pfx/drive_c/users/steamuser/Saved\ Games/kingdomcome2 kingdom-come-2
```

**What happens when you link:**
1. The original save directory is backed up (e.g., `savedir.backup_20231228_120000`)
2. The save files are copied to `~/game-saves/<game_name>/`
3. A symlink is created: original location → `~/game-saves/<game_name>/`
4. The game now writes directly to your Git-tracked directory

### 4. Commit Your Saves

After playing, commit your progress:

```bash
./manage-game-saves.sh commit
```

This stages and commits all changes with a timestamp.

### 5. View Status

Check what's changed:

```bash
./manage-game-saves.sh status
```

## Advanced Usage

### Automatic Backups with Cron

Set up automatic commits every 6 hours:

```bash
crontab -e
```

Add this line:

```
0 */6 * * * ~/game-saves/manage-game-saves.sh auto-commit >> ~/game-saves.log 2>&1
```

Or run daily at midnight:

```
0 0 * * * ~/game-saves/manage-game-saves.sh auto-commit >> ~/game-saves.log 2>&1
```

### Unlink a Game Save

If you want to stop tracking a game or restore the original:

```bash
./manage-game-saves.sh unlink <source_path>
```

This removes the symlink and restores from the most recent backup.

### Restore Old Saves

Use Git to restore previous versions:

```bash
cd ~/game-saves

# View commit history
git log --oneline

# See what changed in a specific save
git show <commit_hash>:alan-wake-2/

# Restore to a previous state
git checkout <commit_hash> -- alan-wake-2/

# Or create a new branch to explore old saves
git checkout -b old-saves <commit_hash>
```

### Finding Game App IDs

Steam games are stored in directories named by App ID. To find which ID belongs to which game:

1. Use the discover command and look at recent saves
2. Check when files were last modified:
   ```bash
   ls -lt ~/.local/share/Steam/steamapps/compatdata/*/pfx/drive_c/users/steamuser/Saved\ Games/
   ```
3. Look up the App ID on [SteamDB](https://steamdb.info/)

## Directory Structure

```
~/game-saves/
├── .git/                    # Git repository
├── .gitignore              # Ignores temp files and caches
├── manage-game-saves.sh    # This script
├── GAME-SAVES-GUIDE.md     # This guide
├── alan-wake-2/            # Linked game saves
├── baldurs-gate-3/
├── clair-obscur/
└── kingdom-come-2/
```

## Common Game Save Locations

### Steam (Proton/Windows games)
- **Saved Games**: `~/.local/share/Steam/steamapps/compatdata/APPID/pfx/drive_c/users/steamuser/Saved Games/`
- **AppData/Local**: `~/.local/share/Steam/steamapps/compatdata/APPID/pfx/drive_c/users/steamuser/AppData/Local/`
- **AppData/LocalLow**: `~/.local/share/Steam/steamapps/compatdata/APPID/pfx/drive_c/users/steamuser/AppData/LocalLow/`
- **AppData/Roaming**: `~/.local/share/Steam/steamapps/compatdata/APPID/pfx/drive_c/users/steamuser/AppData/Roaming/`
- **Documents**: `~/.local/share/Steam/steamapps/compatdata/APPID/pfx/drive_c/users/steamuser/Documents/`

### Heroic Launcher (Epic/GOG)
- **Default prefix**: `~/.config/heroic/Prefixes/default/`
- **Custom prefix**: `~/Games/Heroic/Prefixes/`
- **Wine prefix structure**: `<prefix>/drive_c/users/<username>/AppData/Local/`
- **Flatpak**: `~/.var/app/com.heroicgameslauncher.hgl/`

### Lutris
- **Games directory**: `~/Games/`
- **Wine prefixes**: Custom locations per game (check Lutris config)
- **Flatpak**: `~/.var/app/net.lutris.Lutris/data/games/`

### Wine/Bottles (standalone)
- **Default Wine prefix**: `~/.wine/drive_c/users/<username>/`
- **PlayOnLinux**: `~/.PlayOnLinux/wineprefix/<game>/drive_c/`
- **Bottles**: `~/.local/share/bottles/bottles/<bottle_name>/drive_c/`
- **Bottles Flatpak**: `~/.var/app/com.usebottles.bottles/data/bottles/bottles/<bottle_name>/`

### Native Linux Games
- `~/.local/share/<game or studio name>/`
- `~/.config/<game or studio name>/`
- `~/.config/unity3d/<studio>/<game>/` (Unity games)
- `~/Documents/<game name>/`

### Flatpak Games
- `~/.var/app/<app-id>/data/`
- `~/.var/app/<app-id>/config/`
- Example Steam Flatpak: `~/.var/app/com.valvesoftware.Steam/`

### Snap Games
- `~/snap/<app-name>/current/`
- `~/snap/<app-name>/common/save/`

## Tips

- **Commit regularly**: After each play session or major progress
- **Use descriptive commit messages**: Edit commits with meaningful descriptions
  ```bash
  cd ~/game-saves
  git add alan-wake-2/
  git commit -m "Alan Wake 2: Completed Chapter 5, all collectibles"
  ```
- **Push to remote**: Consider backing up to GitHub/GitLab (use private repo!)
  ```bash
  git remote add origin git@github.com:yourusername/game-saves.git
  git push -u origin main
  ```
- **Large files**: Consider using Git LFS for very large save files
- **Cloud sync**: You can also sync the `~/game-saves` folder with Syncthing or similar
- **Check PCGamingWiki**: For specific game save locations, check [PCGamingWiki](https://www.pcgamingwiki.com/)
- **Use Ludusavi**: Consider [Ludusavi](https://github.com/mtkennerly/ludusavi) for automatic backup of saves across all platforms

## Troubleshooting

### Game doesn't recognize saves after linking
- Make sure the symlink is correct: `ls -la <original_path>`
- Some games may need to be restarted
- Check file permissions match the original

### Symlink already exists
If you get errors about existing symlinks, the game is already linked. Check with:
```bash
ls -la <game_save_path>
```

### Restore from backup
If something goes wrong, your original saves are backed up:
```bash
ls -la <original_path>.backup_*
```

## Commands Reference

```bash
./manage-game-saves.sh init                    # Initialize git repository
./manage-game-saves.sh discover               # Find game save locations
./manage-game-saves.sh link <source> <name>   # Link a game save
./manage-game-saves.sh unlink <source>        # Unlink a game save
./manage-game-saves.sh commit                 # Commit changes
./manage-game-saves.sh auto-commit            # Commit if changes (for cron)
./manage-game-saves.sh status                 # Show git status
```

## Security Note

Never push save files to public repositories - they may contain personal information. Always use private repositories if backing up to remote Git hosting.

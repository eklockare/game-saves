#!/bin/bash

# Game Save Manager - Centralize and version control game saves using symlinks
# This script helps backup game saves to a git repository and creates symlinks
# from the original locations to the backup directory

GAME_SAVES_REPO="$HOME/game-saves"

# Get all mounted drives
get_mounted_drives() {
    df -h | grep -E '^/dev/' | awk '{print $6}'
}

# Find all Steam library locations
find_steam_libraries() {
    local libs=()
    
    # Default location
    if [ -d "$HOME/.local/share/Steam/steamapps" ]; then
        libs+=("$HOME/.local/share/Steam/steamapps")
    fi
    
    # Search for additional Steam libraries on all drives
    local drives=$(get_mounted_drives)
    for drive in $drives; do
        find "$drive" -type d -name "steamapps" -path "*/Steam/*" 2>/dev/null
        find "$drive" -maxdepth 2 -type d -name "steamapps" 2>/dev/null | grep -v "/Steam/"
    done
}

# Find Heroic prefixes
find_heroic_prefixes() {
    find "$HOME/Games" -type d -name "Prefixes" -path "*/Heroic/*" 2>/dev/null
    find "$HOME/.config/heroic" -type d -name "Prefixes" 2>/dev/null
    find "$HOME/.var/app/com.heroicgameslauncher.hgl" -type d 2>/dev/null | head -1
}

# Find Lutris game directories
find_lutris_games() {
    # Lutris native installation
    if [ -d "$HOME/Games" ]; then
        find "$HOME/Games" -maxdepth 2 -type d 2>/dev/null | grep -v "Heroic"
    fi
    
    # Lutris Flatpak
    find "$HOME/.var/app/net.lutris.Lutris" -type d -path "*/data/games/*" 2>/dev/null
}

# Find Wine prefixes (non-Steam, non-Heroic)
find_wine_prefixes() {
    # Default Wine prefix
    [ -d "$HOME/.wine" ] && echo "$HOME/.wine"
    
    # PlayOnLinux
    find "$HOME/.PlayOnLinux/wineprefix" -maxdepth 1 -type d 2>/dev/null
    
    # Bottles
    find "$HOME/.local/share/bottles/bottles" -maxdepth 1 -type d 2>/dev/null
    find "$HOME/.var/app/com.usebottles.bottles/data/bottles/bottles" -maxdepth 1 -type d 2>/dev/null
}

# Find Flatpak/Snap game data
find_flatpak_snap_saves() {
    # Flatpak game data
    find "$HOME/.var/app" -maxdepth 3 -type d \( -path "*/data/*" -o -path "*/config/*" \) 2>/dev/null | \
        grep -iE "save|game" | head -30
    
    # Snap game data
    find "$HOME/snap" -maxdepth 3 -type d -name "save*" -o -name "*game*" 2>/dev/null | head -20
}

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Initialize git repo if it doesn't exist
init_repo() {
    if [ ! -d "$GAME_SAVES_REPO/.git" ]; then
        echo -e "${YELLOW}Initializing git repository at $GAME_SAVES_REPO${NC}"
        mkdir -p "$GAME_SAVES_REPO"
        cd "$GAME_SAVES_REPO"
        git init
        echo "*.tmp" > .gitignore
        echo "*.log" >> .gitignore
        echo "cache/" >> .gitignore
        git add .gitignore
        git commit -m "Initial commit"
    fi
}

# Link a game save directory
# Usage: link_save <source_path> <game_name>
link_save() {
    local source="$1"
    local game_name="$2"
    local dest="$GAME_SAVES_REPO/$game_name"
    
    if [ ! -e "$source" ]; then
        echo -e "${RED}Source does not exist: $source${NC}"
        return 1
    fi
    
    # If source is already a symlink to our repo, skip
    if [ -L "$source" ] && [ "$(readlink -f "$source")" = "$(readlink -f "$dest")" ]; then
        echo -e "${GREEN}✓ $game_name already linked${NC}"
        return 0
    fi
    
    # Backup existing save to repo if not already there
    if [ ! -e "$dest" ]; then
        echo -e "${YELLOW}Copying $game_name to repository...${NC}"
        mkdir -p "$(dirname "$dest")"
        cp -r "$source" "$dest"
    else
        echo -e "${YELLOW}Destination $game_name already exists in repo, syncing...${NC}"
        # Merge any new files from source to dest
        rsync -av --ignore-existing "$source/" "$dest/"
    fi
    
    # Create backup of original if it's not a symlink
    if [ ! -L "$source" ]; then
        local backup_dir="${source}.backup_$(date +%Y%m%d_%H%M%S)"
        echo -e "${YELLOW}Backing up original: $backup_dir${NC}"
        mv "$source" "$backup_dir"
        
        # Create parent directory if needed (in case mv removed it)
        mkdir -p "$(dirname "$source")"
    else
        echo -e "${YELLOW}Removing old symlink${NC}"
        rm "$source"
    fi
    
    # Create symlink (like stow but in reverse)
    echo -e "${GREEN}Creating symlink: $source -> $dest${NC}"
    ln -sf "$dest" "$source"
    
    echo -e "${GREEN}✓ Linked $game_name${NC}"
    echo -e "${YELLOW}Note: You can manage this like a stow package in $dest${NC}"
}

# Unlink a game save (restore from backup)
unlink_save() {
    local source="$1"
    
    if [ -L "$source" ]; then
        echo -e "${YELLOW}Removing symlink: $source${NC}"
        rm "$source"
        
        # Find most recent backup
        local backup=$(ls -t "${source}.backup_"* 2>/dev/null | head -1)
        if [ -n "$backup" ]; then
            echo -e "${GREEN}Restoring from backup: $backup${NC}"
            mv "$backup" "$source"
        fi
    else
        echo -e "${RED}$source is not a symlink${NC}"
    fi
}

# Discover and list game saves
discover_saves() {
    echo -e "${GREEN}=== Discovering game saves on all drives ===${NC}\n"
    
    local steam_libs=$(find_steam_libraries | sort -u)
    local heroic_prefixes=$(find_heroic_prefixes)
    
    echo -e "${YELLOW}Steam Library Locations Found:${NC}"
    echo "$steam_libs" | while read -r lib; do
        [ -n "$lib" ] && echo "  $lib"
    done
    echo ""
    
    echo -e "${YELLOW}Steam (Proton) Saved Games:${NC}"
    echo "$steam_libs" | while read -r lib; do
        [ -z "$lib" ] && continue
        local compat_dir=$(dirname "$lib")/compatdata
        find "$compat_dir" -type d -path "*/pfx/drive_c/users/*/Saved Games/*" 2>/dev/null | \
            grep -v "/cache/" | grep -v "/shaders/" | head -50 | while read -r path; do
            game_id=$(echo "$path" | grep -oP "compatdata/[^/]+" | sed 's/compatdata\///')
            rel_path=$(echo "$path" | sed "s|.*Saved Games/||")
            echo "  [$game_id] $rel_path"
            echo "      $path"
        done
    done
    
    echo -e "\n${YELLOW}Steam AppData Saves (including Baldur's Gate 3):${NC}"
    echo "$steam_libs" | while read -r lib; do
        [ -z "$lib" ] && continue
        local compat_dir=$(dirname "$lib")/compatdata
        
        # Search for save directories in AppData/Local
        find "$compat_dir" -type d -path "*/pfx/drive_c/users/*/AppData/Local/*" 2>/dev/null | \
            grep -iE "save|Larian|Baldur" | head -50 | while read -r path; do
            game_id=$(echo "$path" | grep -oP "compatdata/[^/]+" | sed 's/compatdata\///')
            rel_path=$(echo "$path" | sed "s|.*AppData/Local/||")
            echo "  [$game_id] $rel_path"
            echo "      $path"
        done
        
        # Search for save directories in AppData/LocalLow
        find "$compat_dir" -type d -path "*/pfx/drive_c/users/*/AppData/LocalLow/*" 2>/dev/null | \
            grep -iE "save" | head -30 | while read -r path; do
            game_id=$(echo "$path" | grep -oP "compatdata/[^/]+" | sed 's/compatdata\///')
            rel_path=$(echo "$path" | sed "s|.*AppData/LocalLow/||")
            echo "  [$game_id] $rel_path"
            echo "      $path"
        done
    done
    
    echo -e "\n${YELLOW}Steam Documents/My Games:${NC}"
    echo "$steam_libs" | while read -r lib; do
        [ -z "$lib" ] && continue
        local compat_dir=$(dirname "$lib")/compatdata
        find "$compat_dir" -type d -path "*/pfx/drive_c/users/*/Documents/*" 2>/dev/null | \
            grep -iE "save|My Games" | head -30 | while read -r path; do
            game_id=$(echo "$path" | grep -oP "compatdata/[^/]+" | sed 's/compatdata\///')
            echo "  [$game_id] $path"
        done
    done
    
    echo -e "\n${YELLOW}Heroic Launcher (Epic/GOG) - Alan Wake 2, etc:${NC}"
    echo "$heroic_prefixes" | while read -r prefix_dir; do
        [ -z "$prefix_dir" ] && continue
        echo "  Prefix: $prefix_dir"
        
        # Find saves in Heroic prefixes
        find "$prefix_dir" -type d \( -path "*/AppData/Local/Remedy/*" -o -path "*/AppData/Local/*" -o -path "*/Saved Games/*" \) 2>/dev/null | \
            grep -iE "save|AlanWake|Remedy" | head -30 | while read -r path; do
            echo "    $path"
        done
    done
    
    # Also search Games/Heroic directly
    if [ -d "$HOME/Games/Heroic" ]; then
        find "$HOME/Games/Heroic/Prefixes" -type d -path "*/AppData/Local/*" 2>/dev/null | \
            grep -iE "save|Remedy|AlanWake" | head -20 | while read -r path; do
            echo "    $path"
        done
    fi
    
    echo -e "\n${YELLOW}Lutris Games:${NC}"
    local lutris_games=$(find_lutris_games)
    if [ -n "$lutris_games" ]; then
        echo "$lutris_games" | while read -r game_dir; do
            [ -z "$game_dir" ] && continue
            # Look for Wine prefixes and save directories
            find "$game_dir" -type d \( -path "*/drive_c/users/*/Saved Games/*" -o -path "*/drive_c/users/*/AppData/Local/*" \) 2>/dev/null | \
                grep -iE "save" | head -10 | while read -r path; do
                echo "  $path"
            done
        done
    fi
    
    # Also check Lutris Flatpak
    if [ -d "$HOME/.var/app/net.lutris.Lutris" ]; then
        find "$HOME/.var/app/net.lutris.Lutris" -type d 2>/dev/null | \
            grep -iE "save|wine.*prefix" | head -10 | while read -r path; do
            echo "  $path"
        done
    fi
    
    echo -e "\n${YELLOW}Wine/Bottles Prefixes (non-Steam):${NC}"
    local wine_prefixes=$(find_wine_prefixes)
    if [ -n "$wine_prefixes" ]; then
        echo "$wine_prefixes" | while read -r prefix; do
            [ -z "$prefix" ] && continue
            echo "  Prefix: $prefix"
            # Look for save game directories
            find "$prefix" -type d \( -path "*/drive_c/users/*/Saved Games/*" -o -path "*/drive_c/users/*/AppData/Local/*" -o -path "*/drive_c/users/*/Documents/My Games/*" \) 2>/dev/null | \
                grep -iE "save|my games" | head -10 | while read -r path; do
                echo "    $path"
            done
        done
    fi
    
    echo -e "\n${YELLOW}Native Linux Saves:${NC}"
    echo "  ~/.local/share/<game>:"
    find "$HOME/.local/share" -maxdepth 2 -type d 2>/dev/null | \
        grep -iE "save|game" | grep -v "Steam" | grep -v "Trash" | grep -v "applications" | head -20 | while read -r path; do
        echo "    $path"
    done
    
    echo "  ~/.config/<game>:"
    find "$HOME/.config" -maxdepth 2 -type d 2>/dev/null | \
        grep -iE "save|game" | grep -v "heroic" | grep -v "lutris" | grep -v "gtk" | head -15 | while read -r path; do
        echo "    $path"
    done
    
    # Unity games have a special location
    if [ -d "$HOME/.config/unity3d" ]; then
        echo "  Unity games (~/.config/unity3d):"
        find "$HOME/.config/unity3d" -maxdepth 2 -type d 2>/dev/null | head -10 | while read -r path; do
            echo "    $path"
        done
    fi
    
    echo -e "\n${YELLOW}Flatpak/Snap Game Data:${NC}"
    local flatpak_snap=$(find_flatpak_snap_saves)
    if [ -n "$flatpak_snap" ]; then
        echo "$flatpak_snap" | head -20 | while read -r path; do
            [ -n "$path" ] && echo "  $path"
        done
    fi
    
    echo -e "\n${YELLOW}GOG Galaxy (via Wine/Heroic):${NC}"
    # GOG games through Heroic or Lutris
    if [ -d "$HOME/Games/Heroic" ]; then
        find "$HOME/Games/Heroic" -type d -path "*/GOG/*" 2>/dev/null | head -10 | while read -r path; do
            echo "  $path"
        done
    fi
}

# Commit changes to git
commit_saves() {
    cd "$GAME_SAVES_REPO"
    
    if [ -n "$(git status --porcelain)" ]; then
        echo -e "${YELLOW}Committing changes to git...${NC}"
        git add -A
        git commit -m "Game saves update: $(date '+%Y-%m-%d %H:%M:%S')"
        echo -e "${GREEN}✓ Changes committed${NC}"
    else
        echo -e "${GREEN}No changes to commit${NC}"
    fi
}

# Auto-commit with cron-friendly output
auto_commit() {
    cd "$GAME_SAVES_REPO"
    git add -A
    if [ -n "$(git diff --cached --name-only)" ]; then
        git commit -m "Auto-save: $(date '+%Y-%m-%d %H:%M:%S')" -q
        echo "$(date '+%Y-%m-%d %H:%M:%S'): Game saves committed"
    fi
}

# Show help
show_help() {
    cat << EOF
Game Save Manager - Centralize and version control your game saves

Usage: $0 [command] [options]

Commands:
    init                Initialize git repository
    discover           Discover game save locations
    link <source> <name>   Link a game save directory (reverse-stow style)
    unlink <source>    Unlink a game save directory
    commit             Commit current saves to git
    auto-commit        Commit if changes (cron-friendly)
    status             Show git status
    
About the linking approach:
    This script uses a "reverse stow" approach - instead of stowing FROM the repo
    TO scattered locations (normal stow), we symlink FROM scattered save locations
    TO a centralized git repo. The repo becomes the single source of truth.
    
Examples:
    # Discover all game saves
    $0 discover
    
    # Link Alan Wake 2 saves (if using Heroic/Epic)
    $0 link ~/.var/app/com.heroicgameslauncher.hgl/.../remedy-alan-wake-2 alan-wake-2
    
    # Link Baldur's Gate 3 saves
    $0 link "/path/to/steamapps/compatdata/1086940/pfx/drive_c/users/steamuser/AppData/Local/Larian Studios/Baldur's Gate 3" baldurs-gate-3
    
    # Commit changes
    $0 commit
    
    # Setup automatic commits (add to crontab -e)
    0 */6 * * * $HOME/game-saves/manage-game-saves.sh auto-commit >> ~/game-saves.log 2>&1

EOF
}

# Main script
case "$1" in
    init)
        init_repo
        ;;
    discover)
        discover_saves
        ;;
    link)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo -e "${RED}Error: link requires <source> <name>${NC}"
            echo -e "${YELLOW}This creates a symlink from the original save location to the repo${NC}"
            echo -e "${YELLOW}(Similar to reverse stow - the repo becomes the target)${NC}"
            exit 1
        fi
        init_repo
        link_save "$2" "$3"
        ;;
    unlink)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: unlink requires <source>${NC}"
            exit 1
        fi
        unlink_save "$2"
        ;;
    commit)
        commit_saves
        ;;
    auto-commit)
        auto_commit
        ;;
    status)
        cd "$GAME_SAVES_REPO"
        git status
        ;;
    *)
        show_help
        ;;
esac

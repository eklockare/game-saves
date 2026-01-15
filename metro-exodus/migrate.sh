# Define paths
SOURCE="/home/klockare/game-saves/metro-exodus/76561197963470970"
TARGET="$HOME/.steam/steam/steamapps/compatdata/1449560/pfx/drive_c/users/steamuser/Saved Games/metro exodus/76561197963470970"

# Create target directory
mkdir -p "$TARGET"

# Copy files
cp -r "$SOURCE"/* "$TARGET/"

# Rename files to add _rx suffix (Required by Enhanced Edition)
cd "$TARGET"
for f in m3_*; do
    if [[ "$f" != *"_rx"* ]]; then
        # Example: m3_auto_save -> m3_auto_save_rx
        mv "$f" "${f}_rx"
    fi
done

echo "Migration complete! Your saves are now ready for the Enhanced Edition."

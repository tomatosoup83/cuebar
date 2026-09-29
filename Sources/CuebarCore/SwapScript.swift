import Foundation

/// Builds the detached shell script that swaps the running app for a downloaded
/// one and relaunches. Kept pure so its text is unit-tested.
public enum SwapScript {
    /// `workDirectory` must contain `Cuebar.app` (the staged update) and will be
    /// used for the backup and cleanup.
    public static func make(destination: String, workDirectory: String) -> String {
        """
        #!/bin/sh
        DEST="\(destination)"
        WORK="\(workDirectory)"
        # Wait for the running Cuebar to exit before replacing its bundle.
        while pgrep -x Cuebar >/dev/null 2>&1; do sleep 0.2; done
        rm -rf "$WORK/Cuebar.bak"
        mv "$DEST" "$WORK/Cuebar.bak" 2>/dev/null || true
        if ditto "$WORK/Cuebar.app" "$DEST" && [ -d "$DEST" ]; then
            rm -rf "$WORK/Cuebar.bak"
        else
            rm -rf "$DEST"
            [ -d "$WORK/Cuebar.bak" ] && mv "$WORK/Cuebar.bak" "$DEST"
        fi
        xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
        open "$DEST"
        rm -rf "$WORK"
        """
    }
}

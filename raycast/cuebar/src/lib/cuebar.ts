import { open, showToast, Toast } from "@raycast/api";

/**
 * The `cuebar://` URL scheme, registered by Cuebar.app.
 *
 * The command string is the same thing you would type into the Cuebar palette,
 * so the whole vocabulary — verbs (`pause`, `next`, `shuffle off`), scopes
 * (`album …`, `playlist …`) and bare song names — lives in Cuebar and can't
 * drift from the palette. See `CuebarCore/CuebarURL.swift`.
 */
export function cuebarURL(command: string): string {
  return `cuebar://run?command=${encodeURIComponent(command)}`;
}

/**
 * Hands a command to Cuebar.
 *
 * Cuebar reports the outcome itself (its toast shows "Playing …", "No match
 * for …", a permission problem, and so on), so this deliberately stays quiet
 * unless the URL can't be opened at all — otherwise every command would show
 * two conflicting messages.
 *
 * `open` resolves the scheme through LaunchServices, which launches Cuebar if
 * it isn't running and delivers the URL to it if it is.
 */
export async function runCuebarCommand(command: string): Promise<void> {
  const input = command.trim();
  if (!input) {
    await showToast({
      style: Toast.Style.Failure,
      title: "Type a Cuebar command",
      message: "For example: pause, next, shuffle off, take on me",
    });
    return;
  }

  try {
    await open(cuebarURL(input));
  } catch (error) {
    await showToast({
      style: Toast.Style.Failure,
      title: "Couldn't reach Cuebar",
      message: error instanceof Error ? error.message : String(error),
    });
  }
}

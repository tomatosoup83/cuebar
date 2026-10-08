import { LaunchProps } from "@raycast/api";
import { runCuebarCommand } from "./lib/cuebar";

/**
 * A required text argument, so the command opens with a prompt and can also be
 * pre-filled by a Quicklink or an alias.
 */
type RunCommandArguments = {
  command?: string;
};

export default async function RunCommand(
  props: LaunchProps<{ arguments: RunCommandArguments }>,
) {
  await runCuebarCommand(props.arguments?.command ?? "");
}

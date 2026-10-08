import { runCuebarCommand } from "./lib/cuebar";

export default async function ToggleShuffle() {
  await runCuebarCommand("shuffle");
}

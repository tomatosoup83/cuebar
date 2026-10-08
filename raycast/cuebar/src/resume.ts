import { runCuebarCommand } from "./lib/cuebar";

export default async function Resume() {
  await runCuebarCommand("resume");
}

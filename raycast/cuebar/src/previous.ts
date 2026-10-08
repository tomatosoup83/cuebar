import { runCuebarCommand } from "./lib/cuebar";

export default async function Previous() {
  await runCuebarCommand("previous");
}

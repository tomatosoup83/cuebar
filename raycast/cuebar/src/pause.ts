import { runCuebarCommand } from "./lib/cuebar";

export default async function Pause() {
  await runCuebarCommand("pause");
}

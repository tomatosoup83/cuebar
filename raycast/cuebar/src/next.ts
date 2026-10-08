import { runCuebarCommand } from "./lib/cuebar";

export default async function Next() {
  await runCuebarCommand("next");
}

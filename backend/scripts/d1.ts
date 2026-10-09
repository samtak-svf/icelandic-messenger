// The D1 database of cloudflare.config.ts, for the commands that take its id:
// `cf d1 migrations apply`, `cf d1 query` (scripts/invite-operator.ts). cf
// names a database by id, and the config is the one place it is written.
//
//   node scripts/d1.ts migrate                         # production (migrate:remote)
//   node scripts/d1.ts migrate --local --persist-to .wrangler/state  # cf dev's D1
//
// Runs under plain `node`, like scripts/openapi.ts.

import { spawnSync } from "node:child_process";
import { workerConfig } from "./worker-config.ts";

/** The id of the one D1 database the Worker binds. */
export async function databaseId(): Promise<string> {
  const { env } = await workerConfig();
  const ids = Object.values(env).flatMap((b) => (b.type === "d1" && b.id ? [b.id] : []));
  if (ids.length !== 1)
    throw new Error(`cloudflare.config.ts binds ${ids.length} D1 databases with an id, expected 1`);
  return ids[0] as string;
}

/** Runs `cf d1 <args>` against the database, non-interactively. */
export async function cfD1(
  command: string[],
  args: string[],
  stdout: "inherit" | "ignore" = "inherit",
) {
  const run = spawnSync("pnpm", ["exec", "cf", "d1", ...command, await databaseId(), ...args], {
    stdio: ["ignore", stdout, "inherit"],
  });
  return run.status ?? 1;
}

if (import.meta.main) {
  const [verb, ...rest] = process.argv.slice(2);
  if (verb !== "migrate") {
    console.error("Usage: node scripts/d1.ts migrate [--local --persist-to DIR]");
    process.exit(2);
  }
  process.exit(await cfD1(["migrations", "apply"], ["--dir", "migrations", ...rest]));
}

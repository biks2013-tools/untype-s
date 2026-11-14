// Stills for checking the picture: node tools/stills.ts <lang> <profile> <t1> <t2> ...  -> out/stills/
import { mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { chromium } from "playwright";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const [lang, profile, ...times] = process.argv.slice(2);
const dir = join(root, "out/stills");
mkdirSync(dir, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
page.on("pageerror", (error) => console.error("PAGE ERROR", error.message));
await page.goto(`${pathToFileURL(join(root, "src/untype-demo.html")).href}?lang=${lang}&timing=${profile}&t=0`);
await page.waitForFunction(() => (window as unknown as { __ready?: boolean }).__ready === true);
console.log("duration", await page.evaluate(() => (window as unknown as { __duration: number }).__duration));
for (const t of times) {
  await page.evaluate((x) => (window as unknown as { __seek: (t: number) => void }).__seek(x), Number(t));
  await page.screenshot({ path: join(dir, `${lang}-${t}.jpg`), type: "jpeg", quality: 80 });
}
await browser.close();

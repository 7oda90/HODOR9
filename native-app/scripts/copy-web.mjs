import { cp, mkdir, readFile, writeFile } from 'node:fs/promises';

const root = new URL('../../', import.meta.url);
const out = new URL('../www/', import.meta.url);
await mkdir(out, { recursive: true });
for (const file of ['index.html', 'style.css', 'app.js', 'icon.svg', 'manifest.webmanifest']) {
  await cp(new URL(file, root), new URL(file, out));
}
const htmlPath = new URL('index.html', out);
let html = await readFile(htmlPath, 'utf8');
// Native builds should not register a service worker or show PWA install prompts.
html = html.replace(/<script src="app\.js\?v=[^"]+"><\/script>/, '<script src="app.js"></script>');
await writeFile(htmlPath, html);
let js = await readFile(new URL('app.js', out), 'utf8');
js = js.replace('setupPWA();setInterval(clock,1000);clock();', 'setInterval(clock,1000);clock();');
await writeFile(new URL('app.js', out), js);
console.log('Copied HODOR web app into native-app/www');

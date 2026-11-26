// docs/diagrams/*.mmd -> docs/AtlasRoute-Sinif-Diyagramlari.pdf (A4).
//   PLAYWRIGHT_CORE=<.../node_modules/playwright-core> MERMAID=<.../mermaid/dist/mermaid.min.js> \
//   CHROME=<chromium executable> node docs/diagrams/pdf.mjs
// The .mmd files are the sources; GitHub shows them directly. tests/design.lua checks that
// every class, method and inheritance arrow in them is in the code.
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from 'fs';
import { createRequire } from 'module';
import { tmpdir } from 'os';
import { fileURLToPath } from 'url';
import path from 'path';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_CORE || 'playwright-core');
const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(here, '..', 'AtlasRoute-Sinif-Diyagramlari.pdf');
const mermaidJs = readFileSync(process.env.MERMAID || require.resolve('mermaid/dist/mermaid.min.js'), 'utf8');
const mmd = (f) => readFileSync(path.join(here, f), 'utf8').replace(/&/g, '&amp;').replace(/</g, '&lt;');

const pages = [
  { size: 'portrait', html: `
    <h1>AtlasRoute: sınıf diyagramları, SOLID ve tasarım desenleri</h1>
    <p class="by">Alparslan Tuğra ŞAHİN, Abdülbaki BAYIR, Seyyid Abdülbaki BOZKURT</p>
    <p>AtlasRoute, World of Warcraft için Savaş Takan'ın Atlas algoritmasıyla yol planlayan bir eklentidir.
    Bütün yolculuk biçimleri tek bir grafın süre ağırlıklı kenarlarıdır; planın yapması gereken her şey
    (görev durakları, bir rotanın varışı, uçuş bağlantıları) gerekli bir kenardır ve Atlas hepsini tek
    yürüyüşte kapsar. Aşağıdaki paket görünümünde oklar bağımlılık yönünü gösterir: arayüzler yalnızca
    cepheyi (<code>AtlasPlan</code>), komutları ve veri kaynaklarını bilir; çözücü yalnızca soyutlamaları
    (<code>TravelGraph</code>, <code>ExplorationOrder</code>, <code>ScoringRule</code>) bilir; oyunu ve veri
    kaynaklarını bilmez. Altyapı (sınıf, arayüz, gözlemci) her pakette kullanılır. Ayrıntılar sonraki üç
    sayfadadır.</p>
    <pre class="mermaid">${mmd('1-genel.mmd')}</pre>
    <p class="note">Gösterim (UML): <b>&lt;|--</b> kalıtım, <b>&lt;|..</b> arayüz gerçekleştirme,
    <b>*--</b> bileşim, <b>o--</b> toplama, <b>..&gt;</b> bağımlılık. <b>$</b> ile işaretli yöntemler
    sınıf düzeyindedir (statik). Lua'da sınıf ve arayüz yoktur; <code>core/oop.lua</code> ikisini ekler ve
    bir sınıf arayüzünün yöntemlerinden birini eksik bıraktığında eklenti yüklenirken hata verir.</p>` },
  { size: 'portrait tall', html: `
    <h2>1. Dünya modeli</h2>
    <pre class="mermaid">${mmd('2-dunya.mmd')}</pre>
    <p class="cap"><code>World</code> yerleri, kenarları ve ışınlanmaları tutar. Kimin neyi kullanabileceği
    <code>Gated</code>'dadır (fraksiyon, sınıf, eşya, büyü, beta); kenarlar ve ışınlanmalar ondan türer.
    Bir kenarın süresini kipi hesaplar: <code>TravelMode</code> stratejileri <code>TravelModes</code>
    kayıt defterindedir, yeni bir yolculuk biçimi tek bir <code>register</code> çağrısıdır. İki veri kaynağı
    aynı <code>WorldSource</code> arayüzünü uygular: elle çizilmiş Forever haritası ve oyunun kendi verisi.</p>` },
  { size: 'landscape', html: `
    <h2>2. Graf ve Atlas çözücü</h2>
    <pre class="mermaid">${mmd('3-atlas.mmd')}</pre>
    <p class="cap"><code>AtlasSolver.solve</code> bir şablon yöntemdir: her turda keşfet (DFS ardıl-sıralaması),
    puanla (en uzun yol dinamik programlaması), seç, ekle. Keşif sırası (<code>ExplorationOrder</code>) ve
    puanlama (<code>ScoringRule</code>) değiştirilebilir stratejilerdir; <code>WholeChain</code> Atlas.java'nın
    kuralıdır. Çözücü <code>Observable</code>'dır: her turda ve kapsanan her kenarda olay yayar, oyun bu olayla
    bir sonraki kareye geçer. <code>Atlas</code> ve <code>FSM</code> Java kodunun birebir karşılığıdır;
    <code>FsmGraphAdapter</code> test makinelerini çözücünün grafına uyarlar.</p>` },
  { size: 'landscape', html: `
    <h2>3. Planlama, cephe ve arayüzler</h2>
    <pre class="mermaid">${mmd('4-planlama.mmd')}</pre>
    <p class="cap">Bir planın türü bir <code>Goal</code>'dür: hangi kenarların gerekli olduğunu hazırlar ve
    çözücünün yürüyüşünü cevaba çevirir. <code>AtlasPlanner</code> hedefi çözücüyle çalıştırır;
    <code>AtlasPlan</code> cephesi grafı kurup doğru hedefi seçer. İki eklenti, tanıtım sayfası ve komut satırı
    yalnızca cepheyi kullanır. Eğik çizgili komutlar <code>Command</code> nesneleridir;
    <code>CommandRegistry</code> ayrıştırır ve çalıştırır. «module» etiketli kutular sınıf değil, arayüz modülleridir.</p>` },
  { size: 'portrait', html: `
    <h2>4. SOLID</h2>
    <table>
      <tr><th>İlke</th><th>Kodda</th></tr>
      <tr><td>Tek sorumluluk</td><td><code>Gated</code> yalnızca izin, <code>TravelMode</code> yalnızca süre ve bacak birleştirme,
        <code>TravelGraph</code> yalnızca yapı, <code>AtlasSolver</code> yalnızca algoritma, <code>Goal</code> yalnızca
        ne kapsanacağı, <code>LegAssembler</code> yalnızca sunum, <code>ForeverMap</code>/<code>RetailSnapshot</code>
        yalnızca veri, <code>CommandRegistry</code> yalnızca komut ayrıştırma.</td></tr>
      <tr><td>Açık/kapalı</td><td>Yeni yolculuk biçimi: <code>TravelModes.register</code>. Yeni keşif sırası: bir
        <code>ExplorationOrder</code> sınıfı. Yeni plan türü: bir <code>Goal</code> sınıfı. Yeni komut:
        <code>register</code>. Yeni veri kaynağı: bir <code>WorldSource</code>. Bunların hiçbiri
        <code>AtlasSolver</code>'ı değiştirmez (testi: <i>Open/closed</i>).</td></tr>
      <tr><td>Liskov yerine geçme</td><td>16 keşif sırasının her biri tek başına ve iki puanlama kuralı da geçerli,
        eksiksiz bir tur verir; iki veri kaynağı da aynı planlayıcının kullandığı bir <code>World</code> kurar;
        <code>WalkMode</code> ve <code>FlightMode</code>, <code>FixedMode</code>'un yerine geçer (testler:
        <i>Strategy</i>, <i>Adapter</i>).</td></tr>
      <tr><td>Arayüz ayrımı</td><td>Küçük arayüzler: <code>TravelMode</code> (3 yöntem), <code>ExplorationOrder</code> (2),
        <code>ScoringRule</code> (2), <code>Goal</code> (2), <code>WorldSource</code> (1).</td></tr>
      <tr><td>Bağımlılığın tersine çevrilmesi</td><td><code>AtlasSolver</code> soyutlamalara bağlıdır
        (<code>TravelGraph</code>, <code>ExplorationOrder</code>, <code>ScoringRule</code>); <code>World</code>'ü, oyunu ve
        WoW API'sini bilmez. Arayüzler <code>AtlasPlan</code> cephesine bağlıdır. Stratejiler dışarıdan verilir
        (<code>AtlasSolver.new{orders, scoring}</code>, <code>AtlasPlanner.new(solver)</code>).</td></tr>
    </table>
    <h2>5. Tasarım desenleri</h2>
    <table>
      <tr><th>Desen</th><th>Sınıflar</th><th>Ne için</th></tr>
      <tr><td>Strategy</td><td><code>TravelMode</code>, <code>ExplorationOrder</code>, <code>ScoringRule</code>, <code>Goal</code></td>
        <td>süre hesabı, keşif sırası, zincir puanı, planın türü</td></tr>
      <tr><td>Template Method</td><td><code>AtlasSolver.solve</code></td>
        <td>Atlas turu: <code>explore</code>, <code>score</code>, <code>choose</code>, <code>append</code></td></tr>
      <tr><td>Observer</td><td><code>Observable</code>, <code>AtlasSolver</code></td>
        <td>"round" ve "covered" olayları; oyun her turda kareyi bırakır</td></tr>
      <tr><td>Factory</td><td><code>TravelGraphFactory</code>, <code>ExplorationOrders</code></td>
        <td>karakterin grafı; varsayılan 16 keşif sırası</td></tr>
      <tr><td>Adapter</td><td><code>ForeverMap</code>, <code>RetailSnapshot</code>, <code>FsmGraphAdapter</code></td>
        <td>iki veri kaynağı bir <code>World</code>'e, test makineleri bir <code>TravelGraph</code>'a</td></tr>
      <tr><td>Facade</td><td><code>AtlasPlan</code></td><td>arayüzlerin kullandığı tek giriş</td></tr>
      <tr><td>Command</td><td><code>Command</code>, <code>CommandRegistry</code></td><td>/ar komutları</td></tr>
      <tr><td>Registry</td><td><code>TravelModes</code></td><td>kip adından stratejiye</td></tr>
    </table>
    <p class="note">Diyagramlar koddan elle çizildi ve kodla denetlenir: <code>tests/design.lua</code> her diyagramdaki
    her sınıfın, her yöntemin ve her kalıtım/gerçekleştirme okunun kodda olduğunu, koddaki her sınıfın bir
    diyagramda yer aldığını ve desenlerin davranışını sınar. Kaynaklar <code>docs/diagrams/*.mmd</code>.</p>` },
];

const html = `<!doctype html><html lang="tr"><head><meta charset="utf-8">
<style>
  @page { size: A4 portrait; margin: 14mm; }
  @page portrait { size: A4 portrait; margin: 14mm; }
  @page landscape { size: A4 landscape; margin: 11mm 13mm; }
  body { font-family: "DejaVu Sans", "Noto Sans", Arial, sans-serif; font-size: 9.6pt; color: #1d1d1f; margin: 0; line-height: 1.42; }
  section { break-after: page; }
  section:last-child { break-after: auto; }
  section.portrait { page: portrait; }
  section.landscape { page: landscape; }
  h1 { font-size: 17pt; margin: 0 0 2mm; }
  h2 { font-size: 13pt; margin: 0 0 2mm; }
  .by { color: #555; margin: 0 0 4mm; }
  code { font-family: "DejaVu Sans Mono", monospace; font-size: 8.6pt; }
  .mermaid { display: flex; justify-content: center; margin: 2mm 0; }
  section.landscape .mermaid svg { max-width: 100%; max-height: 158mm; height: auto; }
  section.portrait .mermaid svg { max-width: 100%; max-height: 175mm; height: auto; }
  section.portrait .mermaid { margin: 5mm 0; }
  section.tall .mermaid svg { max-height: 232mm; }
  .cap, .note { font-size: 8.8pt; color: #333; margin: 1mm 0 0; }
  table { border-collapse: collapse; width: 100%; margin: 2mm 0 5mm; font-size: 8.8pt; }
  th, td { border: 0.6pt solid #999; padding: 1.6mm 2mm; text-align: left; vertical-align: top; }
  th { background: #eee; }
</style>
<script>${mermaidJs}</script>
</head><body>
${pages.map((p) => `<section class="${p.size}">${p.html}</section>`).join('\n')}
<script>
  mermaid.initialize({ startOnLoad: false, theme: 'neutral', securityLevel: 'strict',
    flowchart: { htmlLabels: true, curve: 'basis' }, class: { hideEmptyMembersBox: true },
    fontFamily: '"DejaVu Sans", Arial, sans-serif' });
  window.done = mermaid.run({ querySelector: '.mermaid' }).then(() => 'ok',
    (e) => 'error: ' + ((e && (e.message || e.str)) || JSON.stringify(e)));
</script>
</body></html>`;

// The same diagrams as a Markdown page, which GitHub draws (it does not draw .mmd files).
const raw = (f) => readFileSync(path.join(here, f), 'utf8').trimEnd();
const md = ['# AtlasRoute: sınıf diyagramları', '',
  'Kaynaklar bu klasördeki `.mmd` dosyalarıdır; bu sayfa ve `../AtlasRoute-Sinif-Diyagramlari.pdf` onlardan',
  '`node docs/diagrams/pdf.mjs` ile üretilir. `tests/design.lua` diyagramları kodla karşılaştırır.', '',
  ...[['Paketler', '1-genel.mmd'], ['1. Dünya modeli', '2-dunya.mmd'], ['2. Graf ve Atlas çözücü', '3-atlas.mmd'],
      ['3. Planlama, cephe ve arayüzler', '4-planlama.mmd']]
    .flatMap(([title, f]) => ['## ' + title, '', '```mermaid', raw(f), '```', ''])].join('\n');
writeFileSync(path.join(here, 'README.md'), md);

const dir = mkdtempSync(path.join(tmpdir(), 'atlasroute-pdf-'));
const file = path.join(dir, 'diagrams.html');
writeFileSync(file, html);
const browser = await chromium.launch(process.env.CHROME ? { executablePath: process.env.CHROME } : {});
try {
  const page = await browser.newPage();
  await page.goto('file://' + file, { waitUntil: 'load' });
  const status = await page.evaluate(() => window.done);
  if (status !== 'ok') throw new Error('Mermaid: ' + status);
  const rendered = await page.evaluate(() => document.querySelectorAll('.mermaid svg').length);
  if (rendered !== 4) throw new Error(`rendered ${rendered} of 4 diagrams`);
  // Mermaid leaves scratch elements at the end of the body; they would print as a blank page.
  await page.evaluate(() => document.querySelectorAll('body > :not(section)').forEach((n) => n.remove()));
  await page.pdf({ path: out, preferCSSPageSize: true, printBackground: true });
  if (process.env.PNG_DIR) { // page previews for checking the layout
    await page.setViewportSize({ width: 1240, height: 1754 });
    const n = await page.evaluate(() => document.querySelectorAll('section').length);
    for (let i = 0; i < n; i++) {
      const el = (await page.$$('section'))[i];
      await el.screenshot({ path: path.join(process.env.PNG_DIR, `page-${i + 1}.png`) });
    }
  }
  console.log('wrote', out);
} finally {
  await browser.close();
  rmSync(dir, { recursive: true, force: true });
}

/**
 * Code-native store layouts. Gameplay PNGs remain unchanged inside SVG frames.
 * Run with --modules <directory containing sharp>. Use --screenshots-only to
 * refresh the localized screenshot sets without replacing feature graphics.
 */
const fs = require('node:fs/promises');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const moduleIndex = process.argv.indexOf('--modules');
const modules = moduleIndex >= 0 ? process.argv[moduleIndex + 1] : undefined;
const sharp = require(modules ? path.join(modules, 'sharp') : 'sharp');
const metadata = path.join(root, 'fastlane/metadata/android');
const qa = path.join(root, 'store-assets/localized/previews');
const sources = ['0_terrace.png', '5_garden.png', '3_gameplay.png', '4_upgrades_audio.png', '6_results.png', '2_tutorial.png', '7_avatar.png'];
const names = ['00_terrace.jpg', '01_garden.jpg', '02_arcade.jpg', '03_upgrades.jpg', '04_progress.jpg', '05_demo.jpg', '06_avatar.jpg'];
const screenshotsOnly = process.argv.includes('--screenshots-only');
const escape = s => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
const dataImage = async p => `data:image/png;base64,${(await fs.readFile(p)).toString('base64')}`;
const svg = (w,h,contents) => `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${contents}</svg>`;
const font = locale => locale === 'ar' ? ['Segoe UI', 'segoeuib.ttf'] : locale === 'hi-IN' ? ['Nirmala UI', 'Nirmala.ttc'] : locale === 'ja-JP' ? ['Yu Gothic', 'YuGothB.ttc'] : locale === 'ko-KR' ? ['Malgun Gothic', 'malgunbd.ttf'] : ['Segoe UI', 'segoeuib.ttf'];
const measures = [];
async function text(locale, value, width, maxHeight, size, color, align='center') {
  const [family,file] = font(locale);
  for(let pixels=size;pixels>=20;pixels-=2) {
    const {data,info} = await sharp({text:{text:`<span foreground="${color}">${escape(value)}</span>`,font:`${family} Bold ${pixels}`,fontfile:path.join('C:/Windows/Fonts',file),width,align,rgba:true,wrap:'word-char',dpi:72}}).png().toBuffer({resolveWithObject:true});
    if(info.height<=maxHeight) {
      measures.push({locale,value,width:info.width,height:info.height,size:pixels});
      return {data,info};
    }
  }
  throw Error(`Text does not fit: ${locale} ${value}`);
}
const imageTag = (href,x,y,w,h,extra='',fit='slice') => `<image xlink:href="${href}" x="${x}" y="${y}" width="${w}" height="${h}" preserveAspectRatio="xMidYMid ${fit}" ${extra}/>`;
async function makeSlide(locale, copy, i, art, capture, destination) {
  const h1=await text(locale,copy.slides[i][0],940,200,94,'#f6f8dc');
  const sub=await text(locale,copy.slides[i][1],930,90,36,'#d3e3bc');
  const note=await text(locale,copy.footer,920,44,27,'#c5d4bd');
  const brand=await text('en-US','GARDEN NINJA',560,55,35,'#c0ef63');
  // Center the entire device capture in the frame for every display ratio.
  const scale = Math.min(788 / capture.width, 1400 / capture.height);
  const sw = Math.round(capture.width * scale), sh = Math.round(capture.height * scale);
  const sx = Math.round((1080 - sw) / 2), sy = 443 + Math.round((1400 - sh) / 2);
  const base = svg(1080,1920,`
    <defs>
      <linearGradient id="shade" x2="0" y2="1"><stop stop-color="#071f14" stop-opacity=".98"/><stop offset=".3" stop-color="#071f14" stop-opacity=".94"/><stop offset=".72" stop-color="#071f14" stop-opacity=".78"/><stop offset="1" stop-color="#071f14" stop-opacity=".97"/></linearGradient>
      <clipPath id="screen"><rect x="${sx}" y="${sy}" width="${sw}" height="${sh}" rx="10"/></clipPath>
    </defs>
    ${imageTag(art,0,0,1080,1920)}<rect width="1080" height="1920" fill="url(#shade)"/>
    <path d="M0 575 Q70 520 123 589 M1080 1650 Q1025 1605 960 1658" stroke="#d5bd70" opacity=".45" fill="none" stroke-width="3"/>
    <rect x="55" y="58" width="58" height="6" rx="3" fill="#c0ef63"/><rect x="967" y="58" width="58" height="6" rx="3" fill="#c0ef63"/>
    <rect x="${sx - 8}" y="${sy - 8}" width="${sw + 16}" height="${sh + 16}" rx="18" fill="#030d09" stroke="#b8d58c" stroke-opacity=".75" stroke-width="2"/>
    ${imageTag(capture.href,sx,sy,sw,sh,'clip-path="url(#screen)"','meet')}
  `);
  const overlays=[{input:brand.data,top:47,left:Math.round((1080-brand.info.width)/2)},{input:h1.data,top:125,left:Math.round((1080-h1.info.width)/2)},{input:sub.data,top:340,left:Math.round((1080-sub.info.width)/2)},{input:note.data,top:1875,left:Math.round((1080-note.info.width)/2)}];
  await sharp(Buffer.from(base)).composite(overlays).flatten({background:'#071f14'}).jpeg({quality:94,chromaSubsampling:'4:4:4',mozjpeg:true}).toFile(destination);
}
async function makeFeature(locale,copy,art,destination) {
  const brand=await text('en-US','Garden\nNINJA',490,245,110,'#f0ffd7','left');
  const tag=await text(locale,copy.feature,460,113,40,'#d8f99b',locale==='ar'?'right':'left');
  const base=svg(1024,500,`<defs><linearGradient id="shade"><stop stop-color="#04180f" stop-opacity=".98"/><stop offset=".44" stop-color="#04180f" stop-opacity=".9"/><stop offset=".72" stop-color="#04180f" stop-opacity=".12"/><stop offset="1" stop-color="#04180f" stop-opacity=".04"/></linearGradient></defs>${imageTag(art,0,0,1024,500)}<rect width="1024" height="500" fill="url(#shade)"/><rect x="60" y="61" width="69" height="5" rx="2" fill="#b9ec67"/><path d="M60 337 H445" stroke="#cdb878" opacity=".7" stroke-width="2"/>`);
  await sharp(Buffer.from(base)).composite([{input:brand.data,top:91,left:60},{input:tag.data,top:361,left:60}]).flatten({background:'#04180f'}).png({compressionLevel:9}).toFile(destination);
}
async function montage(files,w,h,cols,dest) {
  const layers=[];
  for(let i=0;i<files.length;i++) layers.push({input:await sharp(files[i]).resize(w,h,{fit:'contain',background:'#071f14'}).png().toBuffer(),left:(i%cols)*w,top:Math.floor(i/cols)*h});
  await sharp({create:{width:w*cols,height:h*Math.ceil(files.length/cols),channels:3,background:'#071f14'}}).composite(layers).png().toFile(dest);
}
(async()=>{
  const allCopy=JSON.parse(await fs.readFile(path.join(root,'store-assets/localized/copy.json'),'utf8'));
  await fs.mkdir(qa,{recursive:true});
  const art=await dataImage(path.join(root,'assets/images/splash/garden_ninja_key_art.png'));
  const captures=await Promise.all(sources.map(async name=>{
    const bytes=await fs.readFile(path.join(metadata,'en-US/images/phoneScreenshots',name));
    const {width,height}=await sharp(bytes).metadata();
    return {href:`data:image/png;base64,${bytes.toString('base64')}`,width,height};
  }));
  const features=[],manifest={};
  for(const [locale,copy] of Object.entries(allCopy)) {
    const dir=path.join(metadata,locale,'images');
    await fs.mkdir(path.join(dir,'phoneScreenshots'),{recursive:true});
    const files=[];
    if(copy.slides.length!==sources.length) throw Error(`Expected ${sources.length} slides in ${locale}`);
    for(let i=0;i<sources.length;i++) {const p=path.join(dir,'phoneScreenshots',names[i]);await makeSlide(locale,copy,i,art,captures[i],p);files.push(p);}
    const feature=path.join(dir,'featureGraphic.png');
    if(!screenshotsOnly){await makeFeature(locale,copy,art,feature);features.push(feature);}
    await montage(files,216,384,files.length,path.join(qa,`${locale}-screenshots.png`));
    manifest[locale]={featureGraphic:path.relative(root,feature).replaceAll('\\','/'),phoneScreenshots:files.map(p=>path.relative(root,p).replaceAll('\\','/'))};
    console.log(`${locale}: ${files.length} 1080x1920 screenshots`);
  }
  if(!screenshotsOnly) await montage(features,512,250,2,path.join(qa,'all-feature-graphics.png'));
  await fs.writeFile(path.join(root,'store-assets/localized/manifest.json'),JSON.stringify(manifest,null,2)+'\n');
  await fs.writeFile(path.join(qa,'text-layout.json'),JSON.stringify(measures,null,2)+'\n');
})().catch(error=>{console.error(error);process.exitCode=1;});

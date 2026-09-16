const {chromium}=require(process.env.PLAYWRIGHT_MODULE);
const assert=require('node:assert/strict');
(async()=>{
 const browser=await chromium.connectOverCDP('http://127.0.0.1:9223');
 const page=browser.contexts().flatMap(c=>c.pages()).find(p=>!p.url().includes('overlay=1'));
 const saved=await page.evaluate(()=>localStorage.getItem('linguaglass.preferences.v2'));
 try {
  await page.getByRole('button',{name:'设置',exact:true}).click();
  await page.getByRole('button',{name:'重新检测环境'}).click();
  await page.getByText('本地模型与 GPU 状态已刷新。',{exact:true}).last().waitFor();
  for(const model of ['distil-small.en','distil-medium.en','distil-large-v3']) {
   await page.getByLabel('识别模型').selectOption(model);
   assert.equal(await page.getByLabel('识别模型').inputValue(),model);
  }
  await page.getByLabel('计算设备').selectOption('cuda');
  await page.getByLabel('中文字幕最短停留').selectOption('12');
  await page.keyboard.press('Escape');
  await page.reload();
  await page.getByRole('button',{name:'设置',exact:true}).click();
  assert.equal(await page.getByLabel('计算设备').inputValue(),'cuda');
  assert.equal(await page.getByLabel('中文字幕最短停留').inputValue(),'12');
  await page.keyboard.press('Escape');
  const status=await page.evaluate(()=>window.__TAURI_INTERNALS__.invoke('environment'));
  assert.equal(status.models.length,3); assert.equal(status.cuda_available,true);
  await page.screenshot({path:'artifacts/model-gpu-fixed.png',fullPage:true});
  console.log('MODEL_GPU_UI_OK');
 } finally {
  await page.keyboard.press('Escape');
  await page.evaluate(v=>{if(v===null)localStorage.removeItem('linguaglass.preferences.v2');else localStorage.setItem('linguaglass.preferences.v2',v)},saved);
  await page.evaluate(()=>window.__TAURI_INTERNALS__.invoke('set_overlay',{visible:false,clickThrough:false})).catch(()=>{});
  await browser.close();
 }
})().catch(e=>{console.error(e);process.exitCode=1});


// 设计原型的内容评分和日期边界验证，无浏览器或网络请求。
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'ui/app.js'), 'utf8');
const lastRender = source.lastIndexOf('\nrender();');
assert.ok(lastRender > 0);
const sandbox = {URLSearchParams, location: {search: ''}, console};
vm.createContext(sandbox);
vm.runInContext(source.slice(0, lastRender) + '\nthis.logic={normalize,align,planPreview,state,fixtures,target};', sandbox);
const {normalize,align,planPreview,state,fixtures,target} = sandbox.logic;
const results=[];
function verify(name, fn){fn();results.push({name,passed:true});}
verify('标点与空白不会产生错误',()=>assert.equal(align('学不可以已。','学 不可以已！').accuracy,100));
verify('漏字不会导致后续字符全部错位',()=>{const s=align('学不可以已','学可以已');assert.equal(s.deleted,1);assert.equal(s.substituted,0);assert.equal(s.accuracy,80);});
verify('多说会扣内容一致率',()=>{const s=align('学不可以已','学不可以已可以');assert.equal(s.inserted,2);assert.equal(s.accuracy,60);assert.equal(s.coverage,100);});
verify('没有背出的内容不能被原文补齐',()=>{const s=align(target,fixtures.fail);assert.equal(s.total,29);assert.equal(s.deleted,13);assert.equal(s.coverage.toFixed(1),'55.2');});
verify('达标样例和界面数值一致',()=>{const s=align(target,fixtures.pass);assert.equal(s.accuracy.toFixed(1),'96.6');assert.equal(s.coverage.toFixed(1),'96.6');});
verify('正常化保留原文字而不改字',()=>assert.equal(normalize('积善成德，而神明自得。'),'积善成德而神明自得'));
verify('截止日包含当天且12节需要12个新背日',()=>{state.planStart='2026-10-08';state.planEnd='2026-10-19';state.quota=1;let p=planPreview();assert.equal(p.fits,true);assert.equal(p.finishText,'10月19日');state.planEnd='2026-10-18';assert.equal(planPreview().fits,false);});
verify('周末学习按实际日历分配',()=>{state.planStart='2026-10-10';state.planEnd='2026-10-11';state.weekdays=[6,0];state.quota=6;const p=planPreview();assert.equal(p.fits,true);assert.equal(p.days,2);assert.equal(p.finishText,'10月11日');});
verify('日期倒置、无学习日、未选文章不能创建',()=>{state.planStart='2026-10-12';state.planEnd='2026-10-11';assert.equal(planPreview().fits,false);state.planEnd='2026-10-31';state.weekdays=[];assert.equal(planPreview().fits,false);state.weekdays=[0,1,2,3,4,5,6];state.planArticles=[];assert.equal(planPreview().fits,false);});
function rgb(hex){return hex.slice(1).match(/../g).map(s=>parseInt(s,16)/255).map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4);}
function luminance(hex){const [r,g,b]=rgb(hex);return .2126*r+.7152*g+.0722*b;}
function contrast(a,b){const x=luminance(a),y=luminance(b);return (Math.max(x,y)+.05)/(Math.min(x,y)+.05);}
const manifest=JSON.parse(fs.readFileSync(path.join(root,'docs/design-system/manifest.json'),'utf8'));
verify('正文、辅助说明和主按钮文字符合4.5:1对比度',()=>{for(const c of ['text','secondary','accent'])assert.ok(contrast(manifest.tokens.colors[c],'#FFFFFF')>=4.5);});
fs.mkdirSync(path.join(root,'output/ui'),{recursive:true});
fs.writeFileSync(path.join(root,'output/ui/逻辑验证.json'),JSON.stringify({date:'2026-10-08',scope:'仅设计原型，非真实语音评测',results},null,2));
console.log(`${results.length} 项逻辑与对比度验证通过。`);

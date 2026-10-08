// 将浏览器实际渲染的独立页面裁切为390×844的PNG；不控制浏览器。
const fs=require('node:fs/promises');
const path=require('node:path');
const root=path.resolve(__dirname,'..');
const sharp=require('C:/Users/Administrator/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');
const out=path.join(root,'output/ui');
const names={today:'01-今日',library:'02-文库',import:'03-导入文字',segments:'04-确认分段',planform:'05-新建计划',planview:'06-计划详情',read:'07-阅读练习',record:'08-语音考核',result:'09-达标校对',review:'10-识别待确认',profile:'11-我的',settings:'12-考核规则',failure:'13-未达标校对',empty:'14-文库空状态',typing:'15-文字考核',micerror:'16-录音不可用',account:'17-账户与数据',backup:'18-备份与同步',signin:'19-登录账户',weekly:'20-学习周报',monthly:'21-学习月报',yearly:'22-学习年报'};
(async()=>{
  for(const [id,name] of Object.entries(names)){
    const source=path.join(out,`单页-${id}.jpg`);
    const dims=await sharp(source).metadata();
    if(dims.width<390||dims.height<844)throw Error(`${id}截图尺寸不足`);
    await sharp(source).extract({left:0,top:0,width:390,height:844}).png().toFile(path.join(out,name+'.png'));
  }
  console.log('已从真实页面渲染导出22张中文界面PNG。');
})().catch(e=>{console.error(e);process.exitCode=1;});

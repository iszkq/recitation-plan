"""将真实页面截图排成设计展示板，并绘制中文功能逻辑图。"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'output' / 'ui'
FONT = Path('C:/Windows/Fonts/msyh.ttc')
BOLD = Path('C:/Windows/Fonts/msyhbd.ttc')
BG = '#F7F8FA'
INK = '#1C1C1E'
SECONDARY = '#636366'
BLUE = '#0066CC'

def font(size, bold=False):
    return ImageFont.truetype(str(BOLD if bold else FONT), size)

def write(draw, xy, text, size=18, fill=INK, bold=False):
    draw.text(xy, text, font=font(size,bold), fill=fill)

def multiline(draw, xy, text, width, size=18, fill=SECONDARY, line=29):
    x,y=xy
    for paragraph in text.split('\n'):
        current=''
        for ch in paragraph:
            if draw.textlength(current+ch,font=font(size)) > width and current:
                write(draw,(x,y),current,size,fill); y+=line; current=''
            current+=ch
        if current: write(draw,(x,y),current,size,fill); y+=line
    return y

PAGES=[
 ('01-今日','今日','任务入口'),('02-文库','文库','文章管理'),('03-导入文字','导入文字','粘贴正文'),
 ('04-确认分段','确认分段','可编辑段落'),('05-新建计划','新建计划','配额与截止日'),('06-计划详情','计划详情','排期与进度'),
 ('07-阅读练习','阅读练习','原文与辅助'),('08-语音考核','语音考核','无提示背诵'),('09-达标校对','达标校对','自动完成任务'),
 ('10-识别待确认','识别待确认','回听复核'),('11-我的','我的','学习记录'),('12-考核规则','考核规则','透明判定'),
 ('13-未达标校对','未达标校对','薄弱句重练'),('14-文库空状态','文库空状态','首次使用'),('15-文字考核','文字考核','输入后校对'),('16-录音不可用','录音不可用','恢复路径'),('17-账户与数据','账户与数据','本机档案'),('18-备份与同步','备份与同步','换机恢复'),('19-登录账户','登录账户','按需登录'),('20-学习周报','学习周报','下周重点'),('21-学习月报','学习月报','月度目标'),('22-学习年报','学习年报','长期积累')]

def compose(name, title, subtitle, pages, cols=3):
    margin=51 if cols==3 else 58
    gap=24
    width=margin*2+cols*390+(cols-1)*gap
    rows=(len(pages)+cols-1)//cols
    header=174; caption=34; rowgap=34; footer=60
    height=header+rows*(844+caption)+(rows-1)*rowgap+footer
    image=Image.new('RGB',(width,height),BG);d=ImageDraw.Draw(image)
    write(d,(margin,28),'背诵计划 · 界面设计',15,BLUE)
    write(d,(margin,58),title,32,INK,True)
    multiline(d,(margin,110),subtitle,width-2*margin,size=16,line=25)
    for i,(filename,label,description) in enumerate(pages):
        x=margin+(i%cols)*(390+gap);y=header+(i//cols)*(844+caption+rowgap)
        write(d,(x+3,y),filename[:2],14,BLUE)
        write(d,(x+36,y-2),label,18,INK,True)
        right=draw_width=d.textlength(description,font=font(13))
        write(d,(x+387-right,y+2),description,13,SECONDARY)
        phone=Image.open(OUT/(filename+'.png')).convert('RGB')
        mask=Image.new('L',(390,844),0);md=ImageDraw.Draw(mask);md.rounded_rectangle((0,0,389,843),radius=28,fill=255)
        image.paste(phone,(x,y+caption),mask)
        d.rounded_rectangle((x,y+caption,x+389,y+caption+843),radius=28,outline='#D9DBE0',width=1)
    write(d,(margin,height-37),'纯白简洁 · 系统 iOS 风格 · 语音与成绩为设计演示样例 · 2026年10月8日',13,SECONDARY)
    image.save(OUT/(name+'.png'))

compose('界面图-内容与计划','把一篇文章，变成每天的一小节','导入、确认段落、设定月度目标，再把新背与复习分配到每天。',PAGES[:6])
compose('界面图-背诵与校对','开口背诵，对照原文，达标完成','以最终识别结果判定。疑点先复核，练习与自动通过分别记录。',PAGES[6:12])
compose('界面图-异常与替代路径','每种状态，都有下一步','内容未达标可以重练；没有麦克风权限可以切换文字考核。',PAGES[12:16],2)
compose('界面图-账户与报告','保存进度，看见每一段积累','不登录也可完整学习；按需备份，周报、月报和年报帮助安排下一步。',PAGES[16:])
compose('学习报告','每周有重点，每月有目标，每年有积累','以真实学习事件生成报告；任务完成、考核通过与辅助练习分别统计。',PAGES[19:22])
compose('核心界面','今日任务 → 开口背诵 → 原文校对','按段落完成新背与复习；只有内容达标、无识别疑点的完整考核才自动打卡。',[PAGES[0],PAGES[7],PAGES[8]])

W,H=1320,940
image=Image.new('RGB',(W,H),BG);d=ImageDraw.Draw(image)
write(d,(48,30),'背诵计划 · 功能逻辑',16,BLUE)
write(d,(48,67),'以文章和段落为核心，连接计划、考核与复习',32,INK,True)
write(d,(48,122),'语音和文字共用内容规则；保留原文版本、原始转录、录音及每次考核结果。',17,SECONDARY)
steps=[('01','内容准备','导入全文 → 确认原文\n按段落拆分、合并、排序'),('02','制定计划','选择文章与截止日期\n预览每天新背和复习任务'),('03','今日背诵','阅读 / 遮字 / 分句练习\n进入无提示完整考核'),('04','最终校对','录音结束 → 最终转录\n参考原文辅助对齐与评分')]
for i,(n,title,body) in enumerate(steps):
    x=48+i*312;y=190
    d.rounded_rectangle((x,y,x+288,y+171),radius=16,fill='white',outline='#E5E5EA',width=1)
    write(d,(x+22,y+18),n,14,BLUE)
    write(d,(x+22,y+49),title,22,INK,True)
    multiline(d,(x+22,y+91),body,246,17,SECONDARY,29)
    if i<3:
        d.line((x+292,y+83,x+307,y+83),fill='#8E8E93',width=2)
        d.polygon([(x+308,y+83),(x+302,y+79),(x+302,y+87)],fill='#8E8E93')
# 最终校对引出三种结果。
centers=[244,660,1076]
d.line((1128,362,1128,403),fill='#A9ADB5',width=2)
d.line((244,403,1128,403),fill='#A9ADB5',width=2)
for c in centers:
    d.line((c,403,c,446),fill='#A9ADB5',width=2)
    d.polygon([(c,449),(c-5,441),(c+5,441)],fill='#A9ADB5')
write(d,(488,415),'依据完整会话的最终结果',15,SECONDARY)
decisions=[('#EDF8F1','#187A48','达标且无疑点','自动完成本节任务\n更新掌握进度，生成下次复习\n全部必做任务完成后记当天打卡'),('#FFF6E6','#8B5700','识别待确认','回听对应音频，区分识别偏差\n人工确认单独记录\n重新考核后获得自动通过'),('#FFF0EE','#B42318','内容未达标','标出漏句、错词与薄弱位置\n先练习，再完整重考\n不拼接多次最好片段')]
for i,(bg,color,title,body) in enumerate(decisions):
    x=48+i*416;y=466
    d.rounded_rectangle((x,y,x+392,y+196),radius=16,fill=bg)
    write(d,(x+24,y+25),title,23,color,True)
    multiline(d,(x+24,y+76),body,342,18,INK,31)
d.rounded_rectangle((48,706,1272,866),radius=16,fill='white',outline='#E5E5EA',width=1)
write(d,(72,726),'通过规则示例',21,INK,True)
write(d,(72,769),'一致率 ≥90%    覆盖率 ≥95%    关键项全部正确    无待确认疑点    无辅助提示',18,BLUE)
write(d,(72,810),'新背与复习分别排期；临时转录不打卡；技术识别失败不算背诵失败。',17,SECONDARY)
write(d,(48,902),'第一版逻辑设计 · 阈值需真实中文录音校准 · 所有成绩保留当时规则与原文版本',14,SECONDARY)
image.save(OUT/'功能逻辑图.png')

inventory=[]
for file in sorted(OUT.glob('*.png')):
    with Image.open(file) as im:
        inventory.append({'file':file.name,'width':im.width,'height':im.height})
(OUT/'图片清单.json').write_text(json.dumps(inventory,ensure_ascii=False,indent=2),encoding='utf-8')
print(f'已完成 {len(inventory)} 张 PNG：22个页面、5张展示板、1张核心展示图、1张逻辑图。')

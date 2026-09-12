from PIL import Image
from collections import Counter

im = Image.open(r'E:/celechron-windows/_shot.png').convert('RGB')
W, H = im.size
print('size:', W, 'x', H)
px = im.load()

# 找出内容区（跳过标题栏）
y = 400  # 中部一行
row = [px[x, y] for x in range(W)]
# 找颜色变化点
changes = []
for x in range(1, W):
    if row[x] != row[x-1]:
        changes.append((x, row[x-1], row[x]))
print('row y=%d 变化点前12个:' % y)
for c in changes[:12]:
    print('   x=%4d  %s -> %s' % c)

print()
print('该行出现最多的颜色:')
for col, n in Counter(row).most_common(6):
    print('   %s  %d px' % (col, n))

print()
# 侧边栏宽度：从 x=0 起，颜色与 (0,y) 相同的连续长度
base = px[0, y]
n = 0
while n < W and px[n, y] == base:
    n += 1
print('从 x=0 起同色连续宽度:', n)

# 内容区中心的颜色
print('内容区中心 (550,400) =', px[550, 400])
print('内容区中心 (700,300) =', px[700, 300])
print('内容区中心 (900,500) =', px[900, 500])

# 标题栏高度
colx = 550
ch = []
for yy in range(1, 120):
    if px[colx, yy] != px[colx, yy-1]:
        ch.append((yy, px[colx, yy-1], px[colx, yy]))
print()
print('x=550 纵向变化点(前8):')
for c in ch[:8]:
    print('   y=%4d  %s -> %s' % c)

# 全图颜色统计
allpx = list(im.getdata())
print()
print('全图主要颜色:')
for col, cnt in Counter(allpx).most_common(8):
    print('   %s  %d px  (%.1f%%)' % (col, cnt, cnt*100.0/(W*H)))

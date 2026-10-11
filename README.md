# imm2512
README
360T7 → FUR-602 移植（ImmortalWrt 25.12 / 114M 分区 / bin 固件）
把 ImmortalWrt openwrt-25.12 分支里 360T7 的 MT7981 支持，移植到荣耀 FUR-602
（XT50 / XU50 / XC50 同方案），分区采用 hanwckf U-Boot 的 expand(114m) 布局，
固件产物为 .bin（factory.bin + sysupgrade.bin，非 FIT/itb）。
一、硬件基线
项目
FUR-602
360T7（移植基线）
SoC
MT7981B 双核 A53 @1.3GHz
同
交换
MT7531AE（DSA）
同
内存
256MB DDR3（有 512MB 版本存疑）
256MB DDR3
闪存
128MB SPI-NAND
128MB SPI-NAND
无线
MT7976，AX3000
同（MT7976）
按键
Reset(pio1)、WPS(pio0)
同
指示灯
绿(pio8)、红(pio13)
绿(pio7)、红(pio3)
网口
WAN = 交换口 port0，LAN = port1~3
WAN = port3，LAN = port0~2
网口映射是两者唯一结构性差异，照抄 360T7 会导致 WAN/LAN 对调。
二、114M 分区布局（关键）
原厂 /proc/mtd 实测：
mtd1 00100000 BL2           1M     @0x0000000
mtd2 00080000 u-boot-env   512K    @0x0100000
mtd3 001e0000 Factory      1.875M  @0x0180000
mtd4 00020000 Trace        128K    @0x0360000
mtd5 00200000 FIP          2M      @0x0380000
mtd6 04000000 ubi          64M     @0x0580000
mtd7 00020000 Tracebak     128K    @0x0780000
mtd8 03200000 foxfs        50M     @0x07A0000
刷入 hanwckf U-Boot 后选 expand(114m)，等价于把 ubi 扩到 114MiB：
分区
偏移
大小
DTS 写法
BL2
0x0000000
1M
<0x0 0x100000>
u-boot-env
0x0100000
512K
<0x100000 0x80000>
Factory
0x0180000
1.875M
<0x180000 0x1e0000>
Trace
0x0360000
128K
<0x360000 0x20000>
FIP
0x0380000
2M
<0x380000 0x200000>
ubi
0x0580000
114M
<0x580000 0x7200000>
（保留）
0x7780000
8.5M
不定义
ubi 起点必须落在 0x580000，与 360T7 / CMCC A10 / RAX3000M 完全一致。
114MiB = 0x7200000 = 116736 KiB（对应 IMAGE_SIZE := 116736k）。
若你的 U-Boot 的 mtd layout 是到末尾的 122.5M，把 ubi 改成 <0x580000 0x7a80000>。
以 U-Boot 里 mtdparts 打印为准，两边不一致必定起不来。
三、文件落位
immortalwrt/
├── target/linux/mediatek/dts/mt7981b-honor-fur-602.dts          ← dts/ 目录里的文件
└── target/linux/mediatek/image/filogic.mk                        ← 追加 image/filogic.mk.fur602
make menuconfig 勾选：
Target System: MediaTek Ralink ARM
Subtarget: Filogic 8x0/MT798x
Target Profile: Honor FUR-602
四、固件产物（bin 格式）
bin/targets/mediatek/filogic/
├── immortalwrt-*-mediatek-filogic-honor_fur-602-initramfs-kernel.itb   # 内存版，先试机
├── immortalwrt-*-mediatek-filogic-honor_fur-602-squashfs-factory.bin   # U-Boot 首次刷入
└── immortalwrt-*-mediatek-filogic-honor_fur-602-squashfs-sysupgrade.bin# 系统内升级
factory.bin = append-ubi 生成的完整 UBI 镜像（kernel / rootfs / rootfs_data 卷），
直接写入 ubi 分区；sysupgrade.bin = sysupgrade-tar，只更新 UBI 卷。
五、编译
git clone -b openwrt-25.12 https://github.com/immortalwrt/immortalwrt
cd immortalwrt && ./scripts/feeds update -a && ./scripts/feeds install -a
# 拷入 DTS + 追加设备定义
make menuconfig          # 选 Honor FUR-602
make -j$(nproc) V=s
也可直接 ./apply.sh /path/to/immortalwrt（脚本会自动落位并追加设备定义）。
六、刷机顺序
原厂固件开 SSH（或拆机 TTL），先备份所有 mtd 分区（尤其 Factory 和 FIP）。
刷入 mt7981_honor_fur-602-fip-fixed-parts-multi-layout.bin 到 FIP：
mtd write /tmp/mt7981_honor_fur-602-fip-fixed-parts-multi-layout.bin FIP
断电 → 长按 Reset 上电 → 灯变绿松手，进 U-Boot（PC 设 192.168.1.10，访问 192.168.1.1）。
Choose mtd layout 选 expand(114m)，先上传 initramfs-kernel.itb 试机，
确认网口 / WiFi / LED / 按键正常。
再上传 squashfs-factory.bin 正式刷入，等 1~2 分钟自动重启。
后续升级用 LuCI → 系统 → 备份/升级 → 上传 sysupgrade.bin。
七、刷后核对
cat /proc/mtd                 # ubi 应为 07200000 @ 05800000
cat /proc/partitions
ubinfo -a                     # 应有 kernel / rootfs / rootfs_data 卷
ip link                       # wan = 机身 WAN MAC, lan1~3 = LAN MAC
hexdump -C /dev/mtd3 -s 0x2a -n 6    # LAN MAC，应与机身标签一致
hexdump -C /dev/mtd3 -s 0x24 -n 6    # WAN MAC
hexdump -C /dev/mtd3 -s 0x04 -n 6    # WiFi 基准 MAC
ls /sys/class/leds            # green:status-0 / red:status-1
fw_setenv 若报找不到 env（env 在独立 u-boot-env 分区，不在 UBI 卷里），
写 /etc/fw_env.config：
/dev/mtd1 0x0 0x80000 0x20000
八、需实机确认的可变项
项
当前取值
不对时的现象 / 修正
内存
256MB 0x10000000
free 不足 → 改 0x20000000
LED 电平
GPIO_ACTIVE_LOW
常亮/常灭 → 改 GPIO_ACTIVE_HIGH
LED GPIO
绿 pio8 / 红 pio13
不亮 → 对调或改号
gmac0 链路
2500base-x + fixed-link 2500
网口全不通 → 改 1000base-x / speed 1000
MAC 偏移
LAN 0x2a / WAN 0x24 / WiFi 0x04
MAC 不对 → 按 hexdump 结果调整
NMBM
未启用
与 U-Boot 保持一致；U-Boot 开了 NMBM 才在 &spi_nand 加 mediatek,nmbm
九、如何拿到固件
本环境不能直接编译出固件（只交付移植代码）。实测下载带宽：
源
速度
codeload.github.com
24 KB/s
mirrors.tuna.tsinghua.edu.cn
1 KB/s
downloads.immortalwrt.org
2 KB/s
完整源码 + feeds + dl 包约 23GB，按这个速度要 510 小时且连接随时中断，
无可用代理，因此改为交付可直接编译的产物。两条路：
方案 A：GitHub Actions（推荐，不用本地环境）
新建空仓库，把整个 fur602-imm2512/ 的内容放到仓库根目录
（即仓库里有 dts/、image/、.github/）。
Actions → Build ImmortalWrt 25.12 for Honor FUR-602 → Run workflow。
约 40~80 分钟后在 Artifacts 下载 immortalwrt-2512-honor-fur-602，
内含 *-squashfs-factory.bin、*-squashfs-sysupgrade.bin、*-initramfs-kernel.itb。
方案 B：本地 / 云服务器编译
git clone -b openwrt-25.12 --depth 1 https://github.com/immortalwrt/immortalwrt
cd immortalwrt && ./scripts/feeds update -a && ./scripts/feeds install -a
/path/to/fur602-imm2512/apply.sh .      # 落位 DTS + 设备定义
make menuconfig                          # 选 Honor FUR-602，按需加插件
make download -j$(nproc) && make -j$(nproc) V=s
固件在 bin/targets/mediatek/filogic/。
十、风险
擦除 Factory 分区 = WiFi 报废（EEPROM 在里面），刷机全程不要碰它。
U-Boot 的 mtd layout 与 DTS 分区表必须一致，expand(114m) 对应本文档的 114M；
选 default 原厂布局则会写飞，变砖需 TTL 恢复。
factory.bin 只在 U-Boot 下首次刷入；已在 OpenWrt 系统里刷 factory.bin 会覆盖
UBI 布局，正常升级请用 sysupgrade.bin。

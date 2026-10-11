#!/bin/sh
# 把 FUR-602 移植文件落位到 ImmortalWrt 源码树
# 用法: ./apply.sh /path/to/immortalwrt
set -e

SRC="${1:-.}"
DTS_DIR="$SRC/target/linux/mediatek/dts"
IMG="$SRC/target/linux/mediatek/image/filogic.mk"
HERE=$(cd "$(dirname "$0")" && pwd)

[ -d "$DTS_DIR" ] || { echo "错误: 找不到 $DTS_DIR，请检查源码路径"; exit 1; }
[ -f "$IMG" ]   || { echo "错误: 找不到 $IMG"; exit 1; }

cp "$HERE/dts/mt7981b-honor-fur-602.dts" "$DTS_DIR/"
echo "已写入 $DTS_DIR/mt7981b-honor-fur-602.dts"

if grep -q "define Device/honor_fur-602" "$IMG"; then
	echo "filogic.mk 中已存在 honor_fur-602，跳过"
else
	cat "$HERE/image/filogic.mk.fur602" >> "$IMG"
	echo "已追加设备定义到 $IMG"
fi

echo
echo "完成。接下来："
echo "  cd $SRC && make menuconfig   # Target Profile 选 Honor FUR-602"
echo "  make -j\$(nproc)"

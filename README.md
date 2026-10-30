# 邻里智屏

基于安路 EG4S20BG256 FPGA 的超市前台展示系统。工程通过 TF 卡读取 BMP 图片、PCM 音频与 `CONFIG.TXT`，输出 720p HDMI 画面和音频。支持六张图片常驻缓存、自动轮播、缩略图选择、区域导览、字幕、音频波形及暂停营业通知。

## 工程内容

- `src/td_project/HDMI1.4b_Transmitter_v1.0.al`：TD 工程入口。
- `src/user_source/`：RTL、引脚及时序约束、IP 配置。
- `src/td_project/al_ip/`：项目使用的 IP 配置。
- `src/td_project/tb_*.v`：主要模块的仿真测试文件。
- `build_sixbank_seed2.cmd` 和 `src/td_project/build_sixbank_seed2.tcl`：本机编译脚本。
- `doc/CONFIG.TXT`：TF 卡配置示例；`doc/convert/`：图片及音频准备工具。

目标器件为 EG4S20BG256，原工程使用 TD 6.2.168116。项目文件中的 `Path` 属性和批处理中的 TD 安装路径是原电脑的绝对路径；在其他电脑上打开前，需要改成实际路径。

## TF 卡文件

将 TF 卡格式化为 FAT32，在根目录放置 `PIC1.BMP` 至 `PIC6.BMP`、`AUDIO.PCM`，并可选放置 `CONFIG.TXT`。推荐使用 640×480、24 位未压缩 BMP。`CONFIG.TXT` 使用无 BOM 的 ASCII 文本，示例中提供每张图的停留时间、开机音量和自动轮播开关。实际图片和音乐素材不包含在本仓库中。

导览高亮区域按本地超市布局图设计。若替换 `PIC2.BMP`，需在 `guide_map_overlay` 中重新设置区域与路线坐标。

## 安路 IP

本仓库不发布安路生成且标有版权声明的 Verilog/VHDL，以及加密 HDL。工程中保留了相关 `.ipc` 配置和引用路径。编译前请在 TD 中重新生成对应 IP，并从有授权的官方 HDMI/SDRAM 例程取得受保护模块。未补齐这些文件时，仓库源码不能直接生成比特流。

本仓库不包含旧版本备份、编译日志、比特流、个人报告或 TF 卡媒体文件。

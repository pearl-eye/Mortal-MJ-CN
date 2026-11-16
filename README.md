# Mortal MJ CN

## 简介

Mortal MJ 的国服兼容维护版本，当前基础版本为 **1.0.0.29**，与原版一致。基于 [ChanceRain0108/DalamudPlugins](https://github.com/ChanceRain0108/DalamudPlugins) 的公开编译发布版本，由 pearl-eye 维护 `Emj` / `EmjL` 麻将界面的兼容修复。

插件使用 Mortal AI 为多玛方城战提供建议及自动操作。本仓库提供编译版和使用说明。

修复版的程序集、文件、清单和依赖描述版本均跟随原版，不额外增加小版本号。版本依据见 [upstream-version.json](upstream-version.json)，对应[上游发布提交](https://github.com/ChanceRain0108/DalamudPlugins/commit/57be3ad68fdb0a00877cc106bada1a6686028b44)。打包脚本会拒绝与该依据不一致的版本。兼容修复通过 Git 提交和 Release 说明记录。

## 安装方式

在国服卫月设置的自定义插件仓库中添加并启用：

```text
https://raw.githubusercontent.com/pearl-eye/Dalamud-Plugins-CN/main/repo.json
```

保存后打开插件安装器，搜索 **Mortal MJ CN** 并自行安装。若已安装其他来源的 Mortal MJ，请先禁用旧实例并备份配置，不要同时加载同一插件的多个实例。

早期误标为 `1.0.0.30` 的修复版保留在历史发布中。卫月不会自动降级；已安装该版本时，请先禁用并卸载旧实例，再从上述仓库重新安装 `1.0.0.29`。普通卸载保留配置，勿选择“重置数据”。

使用 `/mjui` 打开设置，`/mjauto` 切换自动出牌，`/mjsetup` 打开环境引导。Mortal 环境沿用原插件入口按需下载，约 300 MB；本插件安装包不包含模型。

进入角色后，原插件会向其原有联机/白名单服务发送**角色名、原始服务器名和 ContentID**，当前默认使用明文 `ws` 连接。本分支保留原有授权检查，不绕过授权或白名单。

## 反馈与贡献

本分支的兼容修复、界面和安装问题，请提交到 [本仓库 Issues](https://github.com/pearl-eye/Mortal-MJ-CN/issues)，并提供插件版本、问题所在界面和复现步骤。原发布版本的说明见 [上游仓库](https://github.com/ChanceRain0108/DalamudPlugins)。

## 许可证与归属

原插件署名为 **ChanceRain、NiGuangOwO、QianChangUwU**，兼容修复由 **pearl-eye** 维护。本分支来自上游公开的编译发布仓库，不代表原作者官方发布。

上游发布仓库未提供 `LICENSE`，本仓库不另行为原插件声明开源许可证。Mortal 引擎、运行环境及模型分别遵循各自的许可证和使用条款。

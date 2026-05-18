# Binky — Roadmap

> 基于审计报告（`docs/audit-report.md` + `docs/audit-review.md`）四轮修复后的剩余工作 + 功能规划。

---

## 已完成（v1.5.x 安全加固）

四轮修复已落地，覆盖 7 个 Critical + 13 个 High/Medium 问题：

- ✅ tar/zip 解压路径穿越防护
- ✅ 应用更新三层签名验证（codesign + BID + team identity）
- ✅ DMG 安装原子化（staging → replaceItemAt）
- ✅ zip 完整性验证后再删源
- ✅ SQLite 持久连接 + WAL + 感知哈希内存索引
- ✅ FSEvents 后台队列
- ✅ ContentInspector OCR 优化 + NSCache 清理
- ✅ 更新脚本时序竞争修复（mv 备份 + 回滚）
- ✅ EnergyConditions / digestFile 取消支持
- ✅ 临时文件检测扩展（.crswap/.opdownload/.aria2/.!ut/~$）
- ✅ 无障碍标签补齐 + 错误反馈 UI + 动画生命周期
- ✅ release.sh --no-push 安全模式
- ✅ 测试覆盖 13 → 49 用例

---

## 短期（v1.6 — 质量收尾）

| 优先级 | 任务 | 工作量 |
|--------|------|--------|
| P1 | Zip 炸弹防护：解压前检查压缩比或设目标大小上限 | 半天 |
| P1 | PostSortShortcutRunner URL 编码修复（`#` 等特殊字符） | 1h |
| P2 | .rar/.7z 规则配置时 UI 提示"不支持解压"或灰掉 extractAndTrash | 2h |
| P2 | 偏好缓存 KVO 失效：监听 `NSUbiquitousKeyValueStoreDidChangeExternallyNotification` 或 `UserDefaults.didChangeNotification` 清缓存 | 2h |
| P2 | FolderWatcher 改用 `Unmanaged.passUnretained` + 外部生命周期管理 | 2h |
| P2 | Sheet 状态机：5 个 Bool → 1 个 `enum ActiveSheet?` 互斥 | 3h |
| P3 | WhereFromsReader 符号链接：加 `XATTR_NOFOLLOW` 标志 | 1h |

---

## 中期（v1.7 — 设计系统 + 本地化健壮性）

| 优先级 | 任务 | 说明 |
|--------|------|------|
| P2 | 品牌色 Asset Catalog 化 | 用 Color Set 提供 light/dark 变体，替代固定 RGB |
| P2 | 按钮/链接样式统一 | 提取 `BinkyButtonStyle` / `BinkyLinkStyle` 组件 |
| P2 | FinderTag 编辑器自适应列宽 | 用 `GridItem(.flexible())` 替代固定 pt |
| P2 | WeeklyDigestShareCard 响应式布局 | 窄窗口降级为竖版 |
| P3 | 侧边栏/Help 窗口最小宽度适配非英语 | 加 `.minimumScaleFactor` 或动态 min width |
| P3 | `.foregroundStyle(.tertiary/.quaternary)` 对比度审查 | 替换为 `.secondary` 或加 opacity 下限 |

---

## 长期（v2.0 — 功能演进）

| 方向 | 内容 |
|------|------|
| **许可证系统** | 一次性购买 + 年度续订更新（存根已在代码中） |
| **Binky + Dinky 捆绑** | 家庭套装定价 |
| **规则合成 v2** | Foundation Models（macOS 26）自然语言 → 规则，回退到启发式 |
| **Watch 文件夹 v2** | 递归深度可配、排除子目录模式 |
| **iCloud 同步** | Routines + Rules 跨设备同步（CloudKit） |
| **Finder Extension** | 原生 Finder 侧边栏集成（替代 Services） |
| **性能仪表盘** | 设置中展示排序耗时趋势、哈希库大小、能量消耗 |
| **插件系统** | 第三方 action（如调用 ImageMagick、ffmpeg） |

---

## 技术债务（持续）

- 测试覆盖目标：核心管线集成测试、撤销操作测试、Watch 防抖测试
- CI 稳定性：修复 LaunchServices "Could not launch BinkyTests" retry 问题
- `tools/` Python 脚本路径从 Dinky 改为 Binky
- 文档：`docs/local-cli.md` 更新 CLI 新命令（tag、routines run）

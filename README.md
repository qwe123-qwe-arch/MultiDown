# 多线程下载器（iOS / SwiftUI）

纯原生、零依赖的 iOS 分片下载器。一个链接切成 N 段，用 N 条 HTTP `Range` 请求并发拉取，写进同一个文件的对应偏移，支持暂停/断点续传。

## 功能

- 1–16 条并发连接（按文件大小自动收敛，小文件不会开一堆连接）
- 自动探测 `Content-Length` / `Accept-Ranges` / `Content-Disposition`
- 服务器不支持 `Range` 时自动退化为单连接，功能不受影响
- 暂停 / 继续（保留每个分片已写入的偏移，真正的断点续传，不是重下）
- 实时进度、已下载/总量、瞬时速度
- 文件落在 App 的 Documents 目录，已开启「文件」App 共享（可在「文件」里直接看到）
- 完成后可分享 / 存储到「文件」

## 目录

```
MultiDown/
├── MultiDown.xcodeproj          # 直接双击打开
│   └── xcshareddata/xcschemes/MultiDown.xcscheme
├── MultiDown/
│   ├── MultiDownApp.swift       # 入口
│   ├── ContentView.swift        # 列表 + 行 UI + 格式化
│   ├── AddDownloadView.swift    # 新建下载
│   ├── DownloadStore.swift      # 任务集合
│   ├── DownloadJob.swift        # 单个任务：HEAD 探测、切片、暂停/恢复
│   ├── DownloadEngine.swift     # 真正的并发 Range 下载 + 落盘
│   └── Assets.xcassets
├── project.yml                  # 可选：XcodeGen 重新生成工程
└── README.md
```

## 编译

要求：Xcode 15+，iOS 16.0+。

1. 双击 `MultiDown.xcodeproj`
2. 选中 target `MultiDown` → Signing & Capabilities → 选自己的 Team，Bundle ID 改成唯一的（如 `com.你的名字.multidown`）
3. 连真机 Run，或 Product → Archive 导出 IPA

### 出无签名 IPA（给 TrollStore / Sideloadly）

```bash
xcodebuild -project MultiDown.xcodeproj -scheme MultiDown \
  -sdk iphoneos -configuration Release \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  -derivedDataPath build
mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/MultiDown.app Payload/
zip -r MultiDown.ipa Payload
```

TrollStore 直接导入这个 ipa；Sideloadly 拖进去用自己的 Apple ID 重签即可。

### 用 XcodeGen 重建工程（可选）

```bash
brew install xcodegen
cd MultiDown && xcodegen generate
```

## 实现要点

- 每个分片一条 `URLSessionDataTask`，`httpMaximumConnectionsPerHost` 设为分片数
- `URLSession` 的 delegate 队列默认串行，所以分片状态不用额外加锁
- 写入用「每个分片一个 FileHandle」，各自 `seek` 到自己的偏移，互不干扰
- 开始时按总大小 `truncate` 出完整文件，避免边写边扩容
- 暂停 = `invalidateAndCancel` 并保存各分片 `received`；继续时用 `Range: bytes=已收到-段末` 续传

## 已知限制

- 前台下载。App 被系统挂起后任务会停（想后台继续需要换成 `URLSession` background configuration 并处理 delegate 重连，工程量翻倍，这版没做）
- 任务列表不持久化，杀掉 App 后列表清空（已下载文件仍在 Documents 里）
- 不支持需要登录态的链接（没有做 Cookie / Header 注入 UI）

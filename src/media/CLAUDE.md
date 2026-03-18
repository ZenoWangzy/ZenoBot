[根目录](../../CLAUDE.md) > [src](../) > **media**

# Media Pipeline

## 模块职责

Media 模块负责 OpenClaw 的媒体处理管道，包括：

1. **图像处理** - 图像转换、缩放、格式化
2. **音频处理** - 音频转码、元数据提取
3. **文件处理** - 文件上传、下载、存储
4. **MIME 检测** - 文件类型识别
5. **FFmpeg 集成** - 音视频转码

## 入口与启动

- 主入口：`host.ts` - 媒体主机
- 存储：`store.ts` - 媒体存储
- 服务器：`server.ts` - 媒体服务器

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `host.ts` | 媒体主机 |
| `store.ts` | 媒体存储 |
| `server.ts` | 媒体服务器 |
| `fetch.ts` | 媒体获取 |

### 图像处理

| 模块 | 职责 |
|------|------|
| `image-ops.ts` | 图像操作 |
| `png-encode.ts` | PNG 编码 |

### 音频处理

| 模块 | 职责 |
|------|------|
| `audio.ts` | 音频处理 |
| `audio-tags.ts` | 音频标签 |
| `ffmpeg-exec.ts` | FFmpeg 执行 |
| `ffmpeg-limits.ts` | FFmpeg 限制 |

### 文件处理

| 模块 | 职责 |
|------|------|
| `input-files.ts` | 输入文件 |
| `outbound-attachment.ts` | 出站附件 |
| `local-roots.ts` | 本地根目录 |
| `temp-files.ts` | 临时文件 |

### MIME 和解析

| 模块 | 职责 |
|------|------|
| `mime.ts` | MIME 类型 |
| `parse.ts` | 解析 |
| `sniff-mime-from-base64.ts` | Base64 MIME 检测 |
| `base64.ts` | Base64 处理 |

### 其他

| 模块 | 职责 |
|------|------|
| `pdf-extract.ts` | PDF 提取 |
| `load-options.ts` | 加载选项 |
| `inbound-path-policy.ts` | 入站路径策略 |
| `constants.ts` | 常量 |

## 关键依赖与配置

### 外部依赖

- `sharp` - 图像处理
- `fluent-ffmpeg` - FFmpeg 包装
- `music-metadata` - 音频元数据

### 配置

```json
{
  "media": {
    "maxSize": 50 * 1024 * 1024,
    "allowedMimes": ["image/*", "audio/*", "application/pdf"],
    "ffmpegPath": "/usr/bin/ffmpeg"
  }
}
```

## 相关文件清单

```
src/media/
├── host.ts                 # 媒体主机
├── store.ts                # 媒体存储
├── server.ts               # 媒体服务器
├── fetch.ts                # 媒体获取
├── image-ops.ts            # 图像操作
├── audio.ts                # 音频处理
├── audio-tags.ts           # 音频标签
├── ffmpeg-exec.ts          # FFmpeg
├── input-files.ts          # 输入文件
├── outbound-attachment.ts  # 出站附件
├── mime.ts                 # MIME
├── parse.ts                # 解析
├── base64.ts               # Base64
├── pdf-extract.ts          # PDF
├── local-roots.ts          # 本地根
├── temp-files.ts           # 临时文件
├── constants.ts            # 常量
└── *.test.ts               # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档

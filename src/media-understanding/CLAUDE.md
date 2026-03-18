[根目录](../../CLAUDE.md) > [src](../) > **media-understanding**

# Media Understanding

## 模块职责

Media Understanding 模块负责媒体文件的智能处理，包括：

1. **附件处理** - 处理图片、视频、音频等附件
2. **音频转录** - 将音频转换为文本
3. **媒体缓存** - 缓存处理过的媒体
4. **预检处理** - 媒体发送前的预检查

## 入口与启动

- 主入口：`attachments.ts`
- 音频转录：`audio-transcription-runner.ts`

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `attachments.ts` | 附件处理主模块 |
| `attachments.cache.ts` | 附件缓存 |
| `attachments.normalize.ts` | 附件规范化 |
| `attachments.select.ts` | 附件选择 |
| `apply.ts` | 内容应用 |

### 音频处理

| 模块 | 职责 |
|------|------|
| `audio-preflight.ts` | 音频预检 |
| `audio-transcription-runner.ts` | 音频转录 |

## 关键依赖与配置

### 依赖

- `sharp` - 图片处理
- `pdfjs-dist` - PDF 解析
- `file-type` - 文件类型检测

### 配置

```json
{
  "mediaUnderstanding": {
    "enabled": true,
    "maxFileSize": 10485760,
    "audioTranscription": {
      "enabled": true,
      "provider": "whisper"
    }
  }
}
```

## 测试与质量

- 测试文件：`*.test.ts`
- 覆盖附件处理、缓存、转录

## 相关文件清单

```
src/media-understanding/
├── attachments.ts                 # 附件处理
├── attachments.cache.ts           # 缓存
├── attachments.normalize.ts       # 规范化
├── attachments.select.ts          # 选择
├── attachments.guards.ts          # 守卫
├── apply.ts                       # 内容应用
├── audio-preflight.ts             # 音频预检
├── audio-transcription-runner.ts  # 音频转录
└── *.test.ts                      # 测试
```

## 相关模块

- [src/media/](../media/CLAUDE.md) - 媒体管道

## 变更记录 (Changelog)

- 2026-03-12: 初始化模块文档

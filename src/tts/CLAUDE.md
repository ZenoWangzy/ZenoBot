[根目录](../../CLAUDE.md) > [src](../) > **tts**

# TTS (Text-to-Speech)

## 模块职责

TTS 模块负责文本转语音功能，包括：

1. **语音合成** - 将文本转换为语音
2. **多语音支持** - 支持多种语音和语言
3. **音频输出** - 输出音频数据或播放

## 入口与启动

- 主入口：`index.ts`

## 对外接口

### 核心组件

| 模块 | 职责 |
|------|------|
| `index.ts` | TTS 导出 |
| `synthesizer.ts` | 语音合成 |
| `voices.ts` | 语音管理 |

## 关键依赖与配置

### 依赖

- `node-edge-tts` - Edge TTS（微软 Azure 语音服务）

### 配置

```json
{
  "tts": {
    "enabled": true,
    "voice": "en-US-JennyNeural",
    "rate": 1.0
  }
}
```

## 测试与质量

- 测试文件：`*.test.ts`

## 相关文件清单

```
src/tts/
├── index.ts           # TTS 导出
├── synthesizer.ts     # 语音合成
├── voices.ts          # 语音管理
└── *.test.ts          # 测试
```

## 变更记录 (Changelog)

- 2026-03-11: 初始化模块文档

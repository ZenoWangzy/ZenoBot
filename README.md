# 🤖 ZenoBot — Personal AI Assistant

<p align="center">
    <picture>
        <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/openclaw/openclaw/main/docs/assets/openclaw-logo-text-dark.png">
        <img src="https://raw.githubusercontent.com/openclaw/openclaw/main/docs/assets/openclaw-logo-text.png" alt="ZenoBot" width="500">
    </picture>
</p>

<p align="center">
  <strong>Zeno 的私人 AI 助手魔改版</strong>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge" alt="MIT License"></a>
</p>

> **Note:** This is a personalized fork of the excellent [OpenClaw](https://github.com/openclaw/openclaw) project, modified and customized by **Zeno** for personal use.

## 关于 ZenoBot

**ZenoBot** 是基于 [OpenClaw](https://openclaw.ai) 的个人 AI 助手魔改版本。OpenClaw 原本是一个运行在你自己设备上的个人 AI 助手，可以在 WhatsApp、Telegram、Slack、Discord、Google Chat、Signal、iMessage、Microsoft Teams、WebChat 等你已经在使用的消息渠道上与你交互。

本项目是 Zeno 对 OpenClaw 的个性化定制版本，包含了一些个人化的修改和优化。

## 原项目特性

OpenClaw 的核心特性包括：

- **多渠道支持**：WhatsApp、Telegram、Slack、Discord、Google Chat、Signal、iMessage、Microsoft Teams、WebChat 等
- **语音交互**：在 macOS/iOS/Android 上进行语音交互
- **Canvas 渲染**：可以渲染实时控制的 Canvas
- **本地控制**：Gateway 只是控制平面，真正的助手产品运行在本地

## 快速开始

Runtime: **Node ≥22**

```bash
# 安装依赖
pnpm install
pnpm ui:build
pnpm build

# 运行向导
pnpm openclaw onboard --install-daemon

# 启动 Gateway
pnpm openclaw gateway --port 18789 --verbose

# 发送消息
pnpm openclaw message send --to +1234567890 --message "Hello from ZenoBot"

# 与助手对话
pnpm openclaw agent --message "Ship checklist" --thinking high
```

## 开发模式

```bash
# 启动 Gateway（自动重载）
pnpm gateway:watch

# 启动 TUI（终端用户界面）
pnpm tui:dev

# 启动 Web UI 开发服务器
pnpm ui:dev
```

## 运行测试

```bash
# 单元测试
pnpm test

# 覆盖率测试
pnpm test:coverage

# E2E 测试
pnpm test:e2e
```

## 支持的模型

- **Anthropic** (Claude Pro/Max) - 推荐
- **OpenAI** (ChatGPT/Codex)

虽然支持任何模型，但强烈推荐 **Anthropic Pro/Max (100/200) + Opus 4.6** 以获得长上下文支持和更好的提示注入防护。

## 原项目文档

- [官网](https://openclaw.ai)
- [文档](https://docs.openclaw.ai)
- [DeepWiki](https://deepwiki.com/openclaw/openclaw)
- [入门指南](https://docs.openclaw.ai/start/getting-started)
- [更新指南](https://docs.openclaw.ai/install/updating)
- [FAQ](https://docs.openclaw.ai/start/faq)

## 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件

## 致谢

本项目基于 [OpenClaw](https://github.com/openclaw/openclaw) 项目，感谢原作者的卓越工作！

---

**Made with ❤️ by Zeno**

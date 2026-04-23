import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { removePathIfExists } from "./runtime-postbuild-shared.mjs";

function symlinkType() {
  return process.platform === "win32" ? "junction" : "dir";
}

function relativeSymlinkTarget(sourcePath, targetPath) {
  const relativeTarget = path.relative(path.dirname(targetPath), sourcePath);
  return relativeTarget || ".";
}

function shouldFallbackToCopy(error) {
  return (
    process.platform === "win32" &&
    (error?.code === "EPERM" || error?.code === "EINVAL" || error?.code === "UNKNOWN")
  );
}

function copyPathFallback(sourcePath, targetPath) {
  removePathIfExists(targetPath);
  const stat = fs.statSync(sourcePath);
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  if (stat.isDirectory()) {
    fs.cpSync(sourcePath, targetPath, { recursive: true, dereference: true });
    return;
  }
  fs.copyFileSync(sourcePath, targetPath);
}

function ensureSymlink(targetValue, targetPath, type, fallbackSourcePath) {
  try {
    fs.symlinkSync(targetValue, targetPath, type);
    return;
  } catch (error) {
    if (fallbackSourcePath && shouldFallbackToCopy(error)) {
      copyPathFallback(fallbackSourcePath, targetPath);
      return;
    }
    if (error?.code !== "EEXIST") {
      throw error;
    }
  }

  try {
    if (fs.lstatSync(targetPath).isSymbolicLink() && fs.readlinkSync(targetPath) === targetValue) {
      return;
    }
  } catch {
    // Fall through and recreate the target when inspection fails.
  }

  removePathIfExists(targetPath);
  try {
    fs.symlinkSync(targetValue, targetPath, type);
  } catch (error) {
    if (fallbackSourcePath && shouldFallbackToCopy(error)) {
      copyPathFallback(fallbackSourcePath, targetPath);
      return;
    }
    throw error;
  }
}

function symlinkPath(sourcePath, targetPath, type) {
  ensureSymlink(relativeSymlinkTarget(sourcePath, targetPath), targetPath, type, sourcePath);
}

function shouldWrapRuntimeJsFile(sourcePath) {
  return path.extname(sourcePath) === ".js";
}

function shouldCopyRuntimeFile(sourcePath) {
  const relativePath = sourcePath.replace(/\\/g, "/");
  return (
    relativePath.endsWith("/package.json") ||
    relativePath.endsWith("/openclaw.plugin.json") ||
    relativePath.endsWith("/.codex-plugin/plugin.json") ||
    relativePath.endsWith("/.claude-plugin/plugin.json") ||
    relativePath.endsWith("/.cursor-plugin/plugin.json")
  );
}

function writeRuntimeModuleWrapper(sourcePath, targetPath) {
  const specifier = relativeSymlinkTarget(sourcePath, targetPath).replace(/\\/g, "/");
  const normalizedSpecifier = specifier.startsWith(".") ? specifier : `./${specifier}`;
  fs.writeFileSync(
    targetPath,
    [
      `export * from ${JSON.stringify(normalizedSpecifier)};`,
      `import * as module from ${JSON.stringify(normalizedSpecifier)};`,
      "export default module.default;",
      "",
    ].join("\n"),
    "utf8",
  );
}

function stagePluginRuntimeOverlay(sourceDir, targetDir) {
  fs.mkdirSync(targetDir, { recursive: true });

  for (const dirent of fs.readdirSync(sourceDir, { withFileTypes: true })) {
    if (dirent.name === "node_modules") {
      continue;
    }

    const sourcePath = path.join(sourceDir, dirent.name);
    const targetPath = path.join(targetDir, dirent.name);

    if (dirent.isDirectory()) {
      stagePluginRuntimeOverlay(sourcePath, targetPath);
      continue;
    }

    if (dirent.isSymbolicLink()) {
      ensureSymlink(fs.readlinkSync(sourcePath), targetPath, undefined, sourcePath);
      continue;
    }

    if (!dirent.isFile()) {
      continue;
    }

    if (shouldWrapRuntimeJsFile(sourcePath)) {
      writeRuntimeModuleWrapper(sourcePath, targetPath);
      continue;
    }

    if (shouldCopyRuntimeFile(sourcePath)) {
      fs.copyFileSync(sourcePath, targetPath);
      continue;
    }

    symlinkPath(sourcePath, targetPath);
  }
}

function linkPluginNodeModules(params) {
  const runtimeNodeModulesDir = path.join(params.runtimePluginDir, "node_modules");
  const distPluginNodeModulesDir = params.distPluginNodeModulesDir;

  removePathIfExists(runtimeNodeModulesDir);

  // Check if dist node_modules exists (after build, dist should have node_modules)
  if (distPluginNodeModulesDir && fs.existsSync(distPluginNodeModulesDir)) {
    // Use dist node_modules if available (already installed by build process)
    fs.symlinkSync(distPluginNodeModulesDir, runtimeNodeModulesDir, symlinkType());
    return;
  }
  ensureSymlink(
    params.sourcePluginNodeModulesDir,
    runtimeNodeModulesDir,
    symlinkType(),
    params.sourcePluginNodeModulesDir,
  );
}

function hasDependencies(pluginDir) {
  const packageJsonPath = path.join(pluginDir, "package.json");
  if (!fs.existsSync(packageJsonPath)) {
    return false;
  }
  try {
    const content = JSON.parse(fs.readFileSync(packageJsonPath, "utf8"));
    return content.dependencies && Object.keys(content.dependencies).length > 0;
  } catch {
    return false;
  }
}

function ensurePluginNodeModules(pluginDir, pluginName) {
  const nodeModulesDir = path.join(pluginDir, "node_modules");
  const packageLockPath = path.join(pluginDir, "package-lock.json");

  // Already installed
  if (fs.existsSync(nodeModulesDir) && fs.existsSync(packageLockPath)) {
    return true;
  }

  // Check if plugin has dependencies to install
  if (!hasDependencies(pluginDir)) {
    return false;
  }

  console.log(`[postbuild] Installing dependencies for ${pluginName}...`);
  const result = spawnSync("npm", ["install", "--omit=dev"], {
    cwd: pluginDir,
    stdio: "pipe",
    shell: process.platform === "win32",
    encoding: "utf8",
  });

  if (result.error) {
    console.error(
      `[postbuild] Failed to install dependencies for ${pluginName}: ${result.error.message}`,
    );
    return false;
  }

  if (result.status !== 0) {
    console.error(`[postbuild] npm install failed for ${pluginName} (exit code ${result.status})`);
    if (result.stderr) {
      console.error(result.stderr);
    }
    return false;
  }

  console.log(`[postbuild] Dependencies installed for ${pluginName}`);
  return true;
}

export function stageBundledPluginRuntime(params = {}) {
  const repoRoot = params.cwd ?? params.repoRoot ?? process.cwd();
  const distRoot = path.join(repoRoot, "dist");
  const runtimeRoot = path.join(repoRoot, "dist-runtime");
  const sourceExtensionsRoot = path.join(repoRoot, "extensions");
  const distExtensionsRoot = path.join(distRoot, "extensions");
  const runtimeExtensionsRoot = path.join(runtimeRoot, "extensions");

  if (!fs.existsSync(distExtensionsRoot)) {
    removePathIfExists(runtimeRoot);
    return;
  }

  removePathIfExists(runtimeRoot);
  fs.mkdirSync(runtimeExtensionsRoot, { recursive: true });

  for (const dirent of fs.readdirSync(distExtensionsRoot, { withFileTypes: true })) {
    if (!dirent.isDirectory()) {
      continue;
    }
    const distPluginDir = path.join(distExtensionsRoot, dirent.name);
    const runtimePluginDir = path.join(runtimeExtensionsRoot, dirent.name);
    const distPluginNodeModulesDir = path.join(distPluginDir, "node_modules");

    // Ensure node_modules exists in dist (auto-install if needed)
    ensurePluginNodeModules(distPluginDir, dirent.name);

    stagePluginRuntimeOverlay(distPluginDir, runtimePluginDir);

    linkPluginNodeModules({
      runtimePluginDir,
      sourcePluginNodeModulesDir: distPluginNodeModulesDir,
      distPluginNodeModulesDir,
    });
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? "").href) {
  stageBundledPluginRuntime();
}

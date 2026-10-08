# 自动构建与 Cachix

[Build and cache](https://github.com/lihaoze123/niri-computer-use/actions/workflows/build.yml)
在 `main` 推送、PR 和手动触发时构建 `x86_64-linux` 包。
工作流使用 `flake.lock` 的固定依赖，不自动升级上游；构建后端时同时运行 Rust 测试，
并检查 Desktop 启动器和 MCP 包装命令。
CI 先构建再运行 `nix flake check --no-build`：后端从补丁后的源码读取 `Cargo.lock`，
首次运行需要先生成该源码路径，才能进行只读求值检查。

## 配置缓存

1. 在 [Cachix](https://app.cachix.org/) 创建公共缓存，或选择已有公共缓存。
2. 在仓库 **Settings → Secrets and variables → Actions → Variables** 中设置
   `CACHIX_CACHE_NAME`，值为实际缓存名称，例如 `niri-computer-use`。
3. 为该缓存生成具有写入权限的 token，在同一设置页的 **Secrets** 中添加
   `CACHIX_AUTH_TOKEN`。不要将 token 或私有签名密钥提交到仓库。
4. 在 Actions 页面选择 **Build and cache → Run workflow → main**，运行首次构建。

也可以用 GitHub CLI 设置名称；添加 secret 时通过交互输入，不把 token 写入命令参数：

```bash
gh variable set CACHIX_CACHE_NAME --repo lihaoze123/niri-computer-use --body niri-computer-use
gh secret set CACHIX_AUTH_TOKEN --repo lihaoze123/niri-computer-use
gh workflow run build.yml --repo lihaoze123/niri-computer-use --ref main
```

只有 `main` 的 push 和手动运行会拿到写入 token、上传构建结果。
PR 只从公共缓存读取，不上传。没有设置缓存名称时仍会构建，但不启用 Cachix；
设置名称但缺少 token 时只读取缓存，主分支运行会给出提示。
公共缓存尚未创建或暂时不可访问时，会提示并继续构建，跳过缓存设置。
每次运行的 Summary 会显示实际缓存状态。

[cachix-action](https://github.com/cachix/cachix-action) 安装 Cachix 并设置下载缓存源。
构建、求值和入口检查全部通过后，通过
[`cachix push`](https://docs.cachix.org/pushing#pushing-runtime-closure)
上传 Desktop、Rust 后端、MCP 包装命令和 `niri-patched` 四个成品包及其运行时依赖，
控制缓存占用。Niri 构建使用 nixpkgs 的标准构建和测试流程；上传失败会使工作流失败。

## 在 NixOS 上使用

先在需要下载缓存的机器上执行以下命令，把名称替换成实际缓存名称：

```bash
cachix use niri-computer-use
```

NixOS 的声明式配置按该命令或 Cachix 的 **Use** 页给出的 URL 和公钥设置：

```nix
{
  nix.settings = {
    extra-substituters = [ "https://<cache-name>.cachix.org" ];
    extra-trusted-public-keys = [ "<Use 页面给出的完整公钥>" ];
  };
}
```

保留系统已有 substituters 和公钥。缓存只命中相同 derivation：系统 flake 中本仓库的
补丁内容和传给它的上游依赖须与 CI 一致。`niri-patched` 使用本仓库独立锁定的
`nixpkgs`，包含两个 Niri 补丁；NixOS 模块仍使用宿主的 `pkgs.niri`，与 CI 共用
`packages/niri.nix`。宿主与 CI 的 nixpkgs、依赖覆盖及 `agentInput = true` 一致时，
模块生成的 Niri 可以命中缓存。只改变无关文件或提交号不会改变该包的 derivation。

单独构建补丁版 Niri：

```bash
nix build .#niri-patched
./result/bin/niri --version
```

更新宿主 nixpkgs 后，可以先将 `flake.nix` 中的 `inputs.nixpkgs.url` 设置为宿主
锁定的 nixpkgs URL，再只更新这个输入：

```bash
nix flake update nixpkgs
```

提交更新后的 `flake.lock` 会触发重新构建并上传。此输入独立于
`codex-desktop-linux` 的 nixpkgs，不会升级 Desktop 或 Rust 后端的依赖。

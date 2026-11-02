# Git Hooks

项目维护者可运行 `git config --local core.hooksPath .githooks` 启用检查。
pre-commit 只检查格式、类型、接口和明显凭据模式，不自动 stage 文件；
commit-msg 验证 Conventional Commits；pre-push 运行 `python scripts/verify.py`。
启用 hooks 不会执行 push，完整测试也可直接在本地运行。

## Pre-commit Hook

This pre-commit hook performs automatic checks before finalizing your commit.

### Usage Instructions

To use this pre-commit hook:

1. Make the hook executable if it isn't already:
   ```bash
   chmod +x .githooks/pre-commit
   ```

2. Configure Git to use the hooks in the .githooks directory:
   ```bash
   git config core.hooksPath .githooks
   ```

3. The hook will automatically run when you execute `git commit`

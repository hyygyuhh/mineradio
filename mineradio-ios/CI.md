# MineRadio-web iOS — GitHub Actions 云端打包

在 **Windows 上改代码 → push GitHub → 云端 macOS 自动编译**，可选产出 `.ipa` 或上传 **TestFlight**。

## 流程概览

```
Windows 编辑代码
    → git push
    → GitHub Actions (macos-14)
    → sync-bridge.sh
    → xcodebuild
    → 模拟器编译（默认，无需签名）
    → [可选] 签名导出 .ipa
    → [可选] 上传 TestFlight
    → Actions Artifacts 下载 ipa
```

工作流文件：`.github/workflows/ios-build.yml`  
构建脚本：`mineradio-ios/scripts/ci-build.sh`

---

## 第一步：把项目推到 GitHub

```bash
git init
git add .
git commit -m "Add MineRadio-web monorepo"
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

---

## 第二步：Apple 开发者准备

需要 [Apple Developer Program](https://developer.apple.com/programs/)（$99/年）才能：

- 真机安装 / Ad Hoc
- TestFlight
- App Store

在 [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources) 中：

1. **App ID**：`art.mineradio.browser`（与 Xcode 工程一致）
2. **Distribution 证书**：Apple Distribution（导出 `.p12`）
3. **Provisioning Profile**：
   - 上传 TestFlight → **App Store** 类型
   - 直接装几台机 → **Ad Hoc**（需登记设备 UDID）

记下：

| 项目 | 示例 |
|------|------|
| Team ID | `AB12CD34EF` |
| Profile 名称 | `MineRadio-web AppStore` |
| 签名身份 | `Apple Distribution` |

---

## 第三步：配置 GitHub Secrets

仓库 → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

### 签名（导出 .ipa 必填）

| Secret 名称 | 内容 |
|-------------|------|
| `IOS_TEAM_ID` | Apple Team ID（10 位） |
| `IOS_PROVISIONING_PROFILE_NAME` | 描述文件**名称**（非 UUID） |
| `IOS_CODE_SIGN_IDENTITY` | `Apple Distribution`（可省略则用默认） |
| `IOS_CERTIFICATE_BASE64` | `.p12` 文件 Base64 |
| `IOS_P12_PASSWORD` | 导出 p12 时设的密码 |
| `IOS_PROVISION_PROFILE_BASE64` | `.mobileprovision` 文件 Base64 |
| `IOS_KEYCHAIN_PASSWORD` | 任意强密码（CI 临时钥匙串用） |

### Base64 编码示例（Mac / Linux）

```bash
base64 -i Certificates.p12 | pbcopy          # 证书 → 粘贴到 IOS_CERTIFICATE_BASE64
base64 -i MineRadio.mobileprovision | pbcopy # 描述文件 → IOS_PROVISION_PROFILE_BASE64
```

Windows PowerShell：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("Certificates.p12"))
[Convert]::ToBase64String([IO.File]::ReadAllBytes("profile.mobileprovision"))
```

### TestFlight 上传（可选）

在 App Store Connect → **用户和访问** → **集成** → **App Store Connect API** 创建密钥：

| Secret 名称 | 内容 |
|-------------|------|
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID |
| `APP_STORE_CONNECT_API_KEY_BASE64` | `AuthKey_XXXX.p8` 的 Base64 |

---

## 第四步：触发构建

### 自动

- 推送到 `main` / `master` 且改动涉及 `mineradio-ios/**` → 自动跑**模拟器编译**
- 若已配置签名 Secrets，**push 到默认分支**还会尝试打 `.ipa`

### 手动

GitHub → **Actions** → **iOS Build** → **Run workflow**

| mode | 作用 |
|------|------|
| `simulator` | 仅验证能编译（无需 Secrets） |
| `ipa` | 签名并导出 `.ipa` |
| `testflight` | 打 ipa + 上传 TestFlight |

---

## 第五步：下载安装包

构建完成后 → **Actions** → 对应 Run → **Artifacts** → 下载 `MineRadio-web-ipa`。

- **TestFlight**：App Store Connect → TestFlight → 添加内部测试员 → iPhone 安装 TestFlight App 接收
- **Ad Hoc ipa**：需对应设备 UDID 已在 Profile 中；用 Apple Configurator / 爱思等工具安装（或企业分发工具）

---

## 本地 Mac 调试同一脚本

```bash
cd mineradio-ios
chmod +x scripts/ci-build.sh scripts/sync-bridge.sh

# 模拟器
./scripts/ci-build.sh simulator

# 真机 ipa（先 export 环境变量，同 Secrets 名称）
export IOS_TEAM_ID=...
export IOS_PROVISIONING_PROFILE_NAME=...
export IOS_CERTIFICATE_BASE64=...
# ...
./scripts/ci-build.sh ipa
```

产物：`mineradio-ios/build/ipa/*.ipa`

---

## 常见问题

**Q: 没有配置 Secrets，CI 会失败吗？**  
不会。默认只跑模拟器编译；IPA 步骤检测到无证书会 **skip**。

**Q: Windows 能直接出 ipa 吗？**  
不能。只能 push 后靠 GitHub Actions 云端 Mac。

**Q: 免费 Apple ID 可以吗？**  
不行。TestFlight / 正式 ipa 都需要付费开发者账号。

**Q: 和 Codemagic / Bitrise 比？**  
原理相同（云端 Mac + xcodebuild）。GitHub Actions 与代码仓库一体，公开库有免费 macOS 分钟额度（私有库需 Actions 付费计划）。

**Q: App Store 审核能通过吗？**  
音源代理类 App 审核风险较高；TestFlight 内测通常更容易。请自备隐私政策与合规说明。

---

## 相关文件

- `.github/workflows/ios-build.yml` — CI 工作流
- `mineradio-ios/scripts/ci-build.sh` — 构建入口
- `mineradio-ios/scripts/sync-bridge.sh` — 同步 Bridge 资源

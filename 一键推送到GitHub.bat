@echo off
chcp 936 >nul
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ==========================================================
echo    DSH iOS 工程 - 一键推送到 GitHub 触发在线编译
echo ==========================================================
echo.

if not exist "project.yml" (
  echo [X] 当前目录没有 project.yml
  echo     请把这个 bat 放在 ios-dsh 目录里再运行
  echo     当前目录: %CD%
  pause
  exit /b 1
)

where git >nul 2>nul
if errorlevel 1 (
  echo [X] 没找到 git，请先装 Git for Windows: https://git-scm.com/download/win
  pause
  exit /b 1
)

echo 推送前请先在 GitHub 网页上建一个空仓库（不要勾选 README / .gitignore）
echo 然后复制它的地址，形如：
echo     https://github.com/你的用户名/dsh-ios.git
echo.
set "REPO_URL="
set /p REPO_URL=仓库地址:

if "%REPO_URL%"=="" (
  echo [X] 仓库地址不能为空
  pause
  exit /b 1
)

echo.
echo [1/5] 准备 .gitignore
> ".gitignore" echo build/
>> ".gitignore" echo build.log
>> ".gitignore" echo Payload/
>> ".gitignore" echo *.ipa
>> ".gitignore" echo *.log
>> ".gitignore" echo __pycache__/
>> ".gitignore" echo DSHMobile.xcodeproj/
>> ".gitignore" echo .DS_Store
echo     完成

echo [2/5] 初始化仓库
if not exist ".git" (
  git init
  git branch -M main
) else (
  echo     已有 .git，跳过
)

echo [3/5] 添加文件
git add -A

echo [4/5] 提交
git -c user.name="dsh" -c user.email="dsh@local" commit -m "DSH iOS client: initial import"
if errorlevel 1 echo     （没有新改动，继续）

echo [5/5] 推送
git remote remove origin >nul 2>nul
git remote add origin "%REPO_URL%"
git push -u origin main
if errorlevel 1 (
  echo.
  echo [X] 推送失败。常见原因：
  echo     1. 没登录 GitHub：弹出登录窗就登，或者用 Personal Access Token 当密码
  echo     2. 仓库不是空的：先删掉仓库里的 README / .gitignore 再试
  echo     3. 分支名不是 main：GitHub 默认分支叫 master 的话改一下
  pause
  exit /b 1
)

echo.
echo ==========================================================
echo   推送完成
echo.
echo   下一步:
echo     1. 打开 GitHub 仓库的 Actions 页面
echo     2. 等 build-ipa 跑完，约 2~4 分钟
echo     3. 进入那次运行，页面底部 Artifacts
echo        下载 DSHMobile-unsigned-ipa，解压得到 .ipa
echo     4. 用 Sideloadly / AltStore / TrollStore 自签安装
echo ==========================================================
pause

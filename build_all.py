#!/usr/bin/env python3
"""
FundLink 跨平台打包脚本
支持 macOS 和 Windows，自动上传到 NAS 和 GitHub Release
打包结果通过 Bark 推送到手机

配置文件：.env（请勿提交到 Git）
模板文件：.env.example（可以提交到 Git）
"""

import subprocess
import sys
import os
import platform
import shutil
from pathlib import Path
from datetime import datetime
import argparse
import getpass
import requests
import json
import re
import tempfile
import time

# 全局变量，用于跟踪上传状态
GITHUB_NETWORK_ERROR = False
UPLOAD_ACTIONS = []  # 记录上传动作: {"platform": "iOS", "action": "覆盖/新上传", "file": "xxx.ipa"}

# 设置控制台编码
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')
    sys.stderr.reconfigure(encoding='utf-8')

# ========== 查找 Flutter 可执行文件绝对路径 ==========
def get_flutter_command():
    which_flutter = shutil.which("flutter")
    if which_flutter:
        return which_flutter
    possible_paths = [
        r"C:\flutter\bin\flutter.bat",
        r"C:\src\flutter\bin\flutter.bat",
        r"C:\Program Files\flutter\bin\flutter.bat",
        str(Path.home() / "flutter/bin/flutter.bat"),
        str(Path.home() / "dev/flutter/bin/flutter.bat"),
        r"D:\flutter\bin\flutter.bat",
        r"D:\Android\flutter\bin\flutter.bat",
    ]
    for p in possible_paths:
        if os.path.exists(p):
            return p
    return "flutter"

FLUTTER_CMD = get_flutter_command()
print(f"🔧 Flutter 命令: {FLUTTER_CMD}")

flutter_dir = os.path.dirname(FLUTTER_CMD)
if flutter_dir and flutter_dir not in os.environ.get("PATH", ""):
    os.environ["PATH"] = flutter_dir + os.pathsep + os.environ.get("PATH", "")

# 加载 .env 文件
from dotenv import load_dotenv

SCRIPT_DIR = Path(__file__).parent.absolute()
ENV_FILE = SCRIPT_DIR / ".env"

if ENV_FILE.exists():
    load_dotenv(ENV_FILE)
    print(f"✅ 加载配置文件: {ENV_FILE}")
else:
    print(f"⚠️  未找到配置文件: {ENV_FILE}")

# ============================================
# 配置区域 - 从环境变量读取
# ============================================

BARK_CONFIG = {
    "enabled": os.getenv("BARK_ENABLED", "true").lower() == "true",
    "url": os.getenv("BARK_URL", ""),
    "group": os.getenv("BARK_GROUP", "打包上传结果通知")
}

GITHUB_CONFIG = {
    "enabled": os.getenv("GITHUB_ENABLED", "true").lower() == "true",
    "token": os.getenv("GITHUB_TOKEN", ""),
    "repo": os.getenv("GITHUB_REPO", "rizona27/fundlink"),
    "tag_name": os.getenv("GITHUB_TAG_NAME") or None,
    "release_name": os.getenv("GITHUB_RELEASE_NAME") or None,
    "draft": os.getenv("GITHUB_DRAFT", "false").lower() == "true",
    "prerelease": os.getenv("GITHUB_PRERELEASE", "false").lower() == "true"
}

NAS_CONFIG = {
    "enabled": os.getenv("NAS_ENABLED", "true").lower() == "true",
    "host": os.getenv("NAS_HOST", ""),
    "port": int(os.getenv("NAS_PORT", "22")),
    "username": os.getenv("NAS_USERNAME", ""),
    "base_path": os.getenv("NAS_BASE_PATH", ""),
    "version_json_path": os.getenv("NAS_VERSION_JSON_PATH", ""),
    "key_path": os.getenv("NAS_KEY_PATH", "~/.ssh/id_rsa"),
    "keep_versions": int(os.getenv("NAS_KEEP_VERSIONS", "5"))
}

PROJECT_CONFIG = {
    "macos_path": os.getenv("MACOS_PROJECT_PATH", ""),
    "windows_path": os.getenv("WINDOWS_PROJECT_PATH", ""),
    "build_output_dir": os.getenv("BUILD_OUTPUT_DIR", "build"),
    "clean_before_build": os.getenv("CLEAN_BEFORE_BUILD", "true").lower() == "true",
    "ios_code_sign": os.getenv("IOS_CODE_SIGN", "false").lower() == "true",
    "android_arch": os.getenv("ANDROID_ARCH", "android-arm64"),
    "build_android_aab": os.getenv("BUILD_ANDROID_AAB", "false").lower() == "true"
}

NAMING_CONFIG = {
    "pattern": os.getenv("NAMING_PATTERN", "FundLink-{version}_{date}"),
    "date_format": os.getenv("DATE_FORMAT", "%m-%d"),
    "ios_ext": os.getenv("IOS_EXT", "ipa"),
    "android_ext": os.getenv("ANDROID_EXT", "apk"),
    "android_aab_ext": os.getenv("ANDROID_AAB_EXT", "aab"),
    "macos_ext": os.getenv("MACOS_EXT", "dmg"),
    "windows_ext": os.getenv("WINDOWS_EXT", "zip")
}

def validate_config():
    errors = []
    if BARK_CONFIG["enabled"] and not BARK_CONFIG["url"]:
        errors.append("BARK_URL 未配置")
    if GITHUB_CONFIG["enabled"]:
        if not GITHUB_CONFIG["token"]:
            errors.append("GITHUB_TOKEN 未配置")
        if not GITHUB_CONFIG["repo"]:
            errors.append("GITHUB_REPO 未配置")
    if NAS_CONFIG["enabled"]:
        if not NAS_CONFIG["host"]:
            errors.append("NAS_HOST 未配置")
        if not NAS_CONFIG["username"]:
            errors.append("NAS_USERNAME 未配置")
        if not NAS_CONFIG["base_path"]:
            errors.append("NAS_BASE_PATH 未配置")
    if errors:
        print("❌ 配置错误:")
        for error in errors:
            print(f"   - {error}")
        return False
    return True

# ============================================
# 主类
# ============================================

class FundLinkBuilder:
    def __init__(self):
        self.current_os = platform.system()
        if self.current_os == "Darwin":
            self.project_dir = Path(PROJECT_CONFIG["macos_path"]) if PROJECT_CONFIG["macos_path"] else SCRIPT_DIR
        elif self.current_os == "Windows":
            self.project_dir = Path(PROJECT_CONFIG["windows_path"]) if PROJECT_CONFIG["windows_path"] else SCRIPT_DIR
        else:
            raise Exception(f"不支持的操作系统: {self.current_os}")
        if not self.project_dir.exists():
            raise Exception(f"项目目录不存在: {self.project_dir}")
        self.version = None
        self.version_code = None
        self.date_suffix = datetime.now().strftime(NAMING_CONFIG["date_format"])
        self.build_results = {}
        self.start_time = datetime.now()
        self.update_logs = []
        self.latest_release_notes = ""

    def send_bark_notification(self, title, body, success=True):
        if not BARK_CONFIG["enabled"] or not BARK_CONFIG["url"]:
            return
        icon = "✅" if success else "❌"
        color = "#4CAF50" if success else "#FF5252"
        full_title = f"{icon} {title}"
        try:
            data = {
                "title": full_title,
                "body": body,
                "group": BARK_CONFIG["group"],
                "color": color,
                "sound": "healthnotification.caf",
                "level": "persistent" if not success else "active",
                "badge": 1
            }
            response = requests.post(BARK_CONFIG["url"], json=data, timeout=10)
            if response.status_code == 200:
                print("📱 推送通知已发送")
        except Exception as e:
            print(f"⚠️  推送通知异常: {e}")

    def send_complete_notification(self):
        duration = datetime.now() - self.start_time
        minutes = int(duration.total_seconds() // 60)
        seconds = int(duration.total_seconds() % 60)
        success_count = sum(1 for r in self.build_results.values() if r.get("success"))
        total_count = len(self.build_results)
        title = "打包完成 [全部成功]" if success_count == total_count else "打包完成 [部分失败]"
        success = (success_count == total_count)
        body_lines = [
            f"版本: {self.version}",
            f"平台: {', '.join(self.build_results.keys())}",
            f"结果: {success_count}/{total_count} 成功",
            f"耗时: {minutes}分{seconds}秒", "",
            "详情:"
        ]
        for name, result in self.build_results.items():
            if result.get("success"):
                nas_status = result.get("nas_action", "未知")
                github_status = result.get("github_action", "未知")
                body_lines.append(f"  ✅ {name}: {result['file_name']} ({result['file_size']}) | NAS:{nas_status} | GitHub:{github_status}")
            else:
                body_lines.append(f"  ❌ {name}: 构建失败")
        body = "\n".join(body_lines)
        self.send_bark_notification(title, body, success)

    def build_failed_notification(self, platform_name, error_msg):
        title = f"{platform_name} 构建失败"
        body = f"版本: {self.version}\n错误: {error_msg[:200]}"
        self.send_bark_notification(title, body, False)

    def get_version_from_pubspec(self):
        pubspec_path = self.project_dir / "pubspec.yaml"
        if not pubspec_path.exists():
            print(f"❌ 找不到 pubspec.yaml: {pubspec_path}")
            return None
        with open(pubspec_path, 'r', encoding='utf-8') as f:
            for line in f:
                if line.strip().startswith('version:'):
                    version_str = line.split(':')[1].strip().strip("'")
                    if '+' in version_str:
                        self.version = version_str.split('+')[0]
                        self.version_code = version_str.split('+')[1]
                    else:
                        self.version = version_str
                        self.version_code = "1"
                    return self.version
        return None

    def parse_update_logs_from_dart(self):
        dart_file = self.project_dir / "lib" / "views" / "version_view.dart"
        if not dart_file.exists():
            print(f"⚠️  找不到 version_view.dart: {dart_file}")
            return []
        logs = []
        in_update_logs = False
        with open(dart_file, 'r', encoding='utf-8') as f:
            for line in f:
                if 'const List<String> UPDATE_LOGS = [' in line:
                    in_update_logs = True
                    continue
                if in_update_logs:
                    if '];' in line or '];' in line.strip():
                        break
                    line = line.strip()
                    match = re.search(r'[\'"]([^\'"]+)[\'"]', line)
                    if match:
                        log_text = match.group(1)
                        if log_text and log_text.strip():
                            logs.append(log_text)
        print(f"📋 从 version_view.dart 解析到 {len(logs)} 条更新日志")
        if logs:
            print(f"   最新: {logs[0][:60]}...")
        return logs

    def get_latest_release_notes(self):
        logs = self.parse_update_logs_from_dart()
        if logs:
            first_log = logs[0]
            if " - " in first_log:
                return first_log.split(" - ", 1)[1]
            return first_log
        return "版本更新"

    def run_command(self, cmd, cwd=None, capture_output=True, timeout=3600):
        if isinstance(cmd, list) and cmd and cmd[0] == "flutter":
            cmd = [FLUTTER_CMD] + cmd[1:]
        elif isinstance(cmd, str) and cmd.startswith("flutter "):
            cmd = cmd.replace("flutter", FLUTTER_CMD, 1)
        print(f"执行: {' '.join(cmd) if isinstance(cmd, list) else cmd}")
        try:
            if capture_output:
                result = subprocess.run(
                    cmd, shell=isinstance(cmd, str),
                    cwd=cwd, text=True,
                    capture_output=True,
                    timeout=timeout,
                    encoding='utf-8', errors='replace'
                )
                if result.returncode != 0:
                    if result.stderr:
                        print(f"⚠️  错误: {result.stderr[:200]}")
                    return False, result.stderr
                return True, result.stdout
            else:
                process = subprocess.Popen(
                    cmd, shell=isinstance(cmd, str),
                    cwd=cwd, text=True,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    encoding='utf-8', errors='replace'
                )
                stdout_lines = []
                stderr_lines = []
                for line in process.stdout:
                    print(line, end='')
                    stdout_lines.append(line)
                for line in process.stderr:
                    print(line, end='', file=sys.stderr)
                    stderr_lines.append(line)
                process.wait(timeout=timeout)
                if process.returncode != 0:
                    error_msg = ''.join(stderr_lines[-500:]) if stderr_lines else "未知错误"
                    return False, error_msg
                return True, ''.join(stdout_lines)
        except subprocess.TimeoutExpired:
            print(f"❌ 命令执行超时 ({timeout}秒)")
            return False, "超时"
        except Exception as e:
            print(f"❌ 执行命令时出错: {e}")
            return False, str(e)

    def unlock_ssh_key(self):
        if not NAS_CONFIG["enabled"]:
            return True
        key_path = os.path.expanduser(NAS_CONFIG["key_path"])
        if not os.path.exists(key_path):
            print(f"⚠️  SSH 私钥不存在: {key_path}")
            return False
        result = subprocess.run(['ssh-keygen', '-y', '-f', key_path], capture_output=True, text=True)
        if result.returncode == 0:
            print("✅ SSH 密钥无需密码")
            return True
        result = subprocess.run(['ssh-add', '-l'], capture_output=True, text=True)
        key_name = os.path.basename(key_path)
        if key_name in result.stdout:
            print("✅ SSH 密钥已解锁")
            return True
        print("\n" + "="*50)
        print("🔐 SSH 密钥认证")
        print("="*50)
        print(f"密钥路径: {key_path}")
        for attempt in range(3):
            try:
                passphrase = getpass.getpass(f"请输入 SSH 密钥密码 (尝试 {attempt + 1}/3): ")
                process = subprocess.run(['ssh-add', key_path],
                                        input=passphrase, text=True,
                                        capture_output=True)
                if process.returncode == 0:
                    print("✅ SSH 密钥解锁成功！")
                    return True
                else:
                    print("❌ 密码错误")
            except KeyboardInterrupt:
                print("\n⚠️  已取消")
                return False
        print("❌ 多次尝试失败，将跳过 NAS 上传")
        NAS_CONFIG["enabled"] = False
        return False

    def upload_to_github_release(self, local_path, platform_name):
        """上传文件到 GitHub Release，如果存在同名则先删除"""
        global GITHUB_NETWORK_ERROR
        if not GITHUB_CONFIG["enabled"]:
            return False, "未启用"
        if GITHUB_NETWORK_ERROR:
            return False, "网络错误，已跳过"
        
        local_path = Path(local_path)
        if not local_path.exists():
            return False, "文件不存在"
        
        tag = GITHUB_CONFIG["tag_name"] or f"v{self.version}"
        file_name = local_path.name
        print(f"📤 上传到 GitHub Release: {file_name}")
        
        headers = {"Authorization": f"token {GITHUB_CONFIG['token']}", "Accept": "application/vnd.github.v3+json"}
        
        try:
            # 获取或创建 Release
            release_url = f"https://api.github.com/repos/{GITHUB_CONFIG['repo']}/releases/tags/{tag}"
            response = requests.get(release_url, headers=headers, timeout=30)
            action = "新上传"
            release_info = None
            
            if response.status_code == 404:
                print(f"📝 创建 Release: {tag}")
                create_data = {
                    "tag_name": tag,
                    "name": GITHUB_CONFIG["release_name"] or f"FundLink {self.version}",
                    "body": self.latest_release_notes,
                    "draft": GITHUB_CONFIG["draft"],
                    "prerelease": GITHUB_CONFIG["prerelease"]
                }
                response = requests.post(
                    f"https://api.github.com/repos/{GITHUB_CONFIG['repo']}/releases",
                    headers=headers, json=create_data, timeout=30
                )
                if response.status_code not in [201, 200]:
                    return False, f"创建Release失败: {response.status_code}"
                release_info = response.json()
                action = "新创建 Release 并上传"
            elif response.status_code == 200:
                release_info = response.json()
            else:
                return False, f"获取 Release 失败: {response.status_code}"
            
            if not release_info:
                return False, "无法获取 Release 信息"
            
            upload_url = release_info.get("upload_url", "").split("{")[0]
            release_id = release_info.get("id")
            
            # 检查并删除同名资产
            assets_url = f"https://api.github.com/repos/{GITHUB_CONFIG['repo']}/releases/{release_id}/assets"
            assets_response = requests.get(assets_url, headers=headers, timeout=30)
            if assets_response.status_code == 200:
                for asset in assets_response.json():
                    if asset["name"] == file_name:
                        print(f"⚠️  发现同名资产 {file_name}，正在删除...")
                        del_response = requests.delete(asset["url"], headers=headers, timeout=30)
                        if del_response.status_code in [204, 200]:
                            print("✅ 旧资产已删除")
                            action = "覆盖上传 (已删除旧文件)"
                        else:
                            print(f"⚠️  删除旧资产失败: {del_response.status_code}，尝试继续上传")
                        break
            
            # 上传新文件
            upload_url_with_name = f"{upload_url}?name={file_name}"
            with open(local_path, 'rb') as f:
                file_content = f.read()
            upload_headers = {"Authorization": f"token {GITHUB_CONFIG['token']}", 
                            "Content-Type": "application/octet-stream", 
                            "Content-Length": str(len(file_content))}
            response = requests.post(upload_url_with_name, headers=upload_headers, data=file_content, timeout=300)
            if response.status_code in [201, 200]:
                print(f"✅ GitHub 上传成功: {file_name}")
                return True, action
            else:
                return False, f"上传失败: {response.status_code}"
                
        except requests.exceptions.Timeout:
            print(f"⚠️  GitHub API 连接超时")
            GITHUB_NETWORK_ERROR = True
            return False, "连接超时"
        except requests.exceptions.ConnectionError:
            print(f"⚠️  GitHub API 连接错误")
            GITHUB_NETWORK_ERROR = True
            return False, "连接错误"
        except Exception as e:
            return False, str(e)

    def upload_to_nas(self, local_path, remote_subdir, platform_name):
        """上传文件到 NAS，直接覆盖"""
        if not NAS_CONFIG["enabled"]:
            return False, "未启用"
        
        local_path = Path(local_path)
        if not local_path.exists():
            return False, "文件不存在"
        
        remote_dir = f"{NAS_CONFIG['base_path']}{remote_subdir}/"
        remote_filename = local_path.name
        remote_path = f"{remote_dir}{remote_filename}"
        file_size_mb = local_path.stat().st_size / 1024 / 1024
        print(f"📤 上传到 NAS: {remote_subdir}/{remote_filename} ({file_size_mb:.2f} MB)")

        # 检查 NAS 上是否已存在同名文件
        check_cmd = f'ssh -p {NAS_CONFIG["port"]} {NAS_CONFIG["username"]}@{NAS_CONFIG["host"]} "test -f {remote_path} && echo exists || echo notexist"'
        result = subprocess.run(check_cmd, shell=True, capture_output=True, text=True, timeout=30)
        file_exists = "exists" in result.stdout
        
        # 创建目录
        mkdir_cmd = f'ssh -p {NAS_CONFIG["port"]} {NAS_CONFIG["username"]}@{NAS_CONFIG["host"]} "mkdir -p {remote_dir}"'
        self.run_command(mkdir_cmd, capture_output=True, timeout=30)

        # 上传（直接覆盖）
        try:
            with open(local_path, 'rb') as f:
                ssh_cmd = ['ssh', '-p', str(NAS_CONFIG["port"]), f"{NAS_CONFIG['username']}@{NAS_CONFIG['host']}", f"cat > {remote_path}"]
                process = subprocess.Popen(ssh_cmd, stdin=subprocess.PIPE)
                process.communicate(input=f.read(), timeout=300)
                if process.returncode != 0:
                    return False, "上传失败"
        except Exception as e:
            return False, str(e)
        
        action = "覆盖上传" if file_exists else "新上传"
        print(f"✅ NAS 上传成功: {remote_subdir}/{remote_filename} ({action})")

        # 清理旧版本
        ext = local_path.suffix[1:]
        cleanup_cmd = f'ssh -p {NAS_CONFIG["port"]} {NAS_CONFIG["username"]}@{NAS_CONFIG["host"]} "cd {remote_dir} && ls -t *.{ext} 2>/dev/null | tail -n +{NAS_CONFIG["keep_versions"] + 1} | xargs -r rm -f"'
        subprocess.run(cleanup_cmd, shell=True, timeout=30, capture_output=True)
        return True, action

    def update_version_json(self):
        if not NAS_CONFIG["enabled"]:
            return True
        print("\n" + "="*50)
        print("📝 更新 version.json")
        print("="*50)
        today = datetime.now().strftime("%Y-%m-%d")
        ios_file = self.build_results.get('iOS', {}).get('file_name', 'FundLink.ipa')
        android_file = self.build_results.get('Android', {}).get('file_name', 'app-release.apk')
        macos_file = self.build_results.get('macOS', {}).get('file_name', 'FundLink.dmg')
        windows_file = self.build_results.get('Windows', {}).get('file_name', 'FundLink.zip')
        release_notes = self.get_latest_release_notes()
        version_data = {
            "version": self.version,
            "versionCode": self.version_code or "1",
            "releaseDate": today,
            "releaseNotes": release_notes,
            "downloads": {
                "ios": {"url": f"/downloads/ios/{ios_file}"},
                "android": {"url": f"/downloads/android/{android_file}"},
                "windows": {"url": f"/downloads/windows/{windows_file}"},
                "macos": {"url": f"/downloads/macos/{macos_file}"}
            }
        }
        temp_json = Path(tempfile.gettempdir()) / "version.json"
        with open(temp_json, 'w', encoding='utf-8') as f:
            json.dump(version_data, f, indent=2, ensure_ascii=False)
        print(f"版本: {self.version}")
        print(f"版本号: {self.version_code}")
        print(f"发布日期: {today}")
        print(f"更新内容: {release_notes}")
        remote_path = NAS_CONFIG["version_json_path"]
        print(f"📤 上传到: {remote_path}")
        try:
            with open(temp_json, 'rb') as f:
                ssh_cmd = ['ssh', '-p', str(NAS_CONFIG["port"]), f"{NAS_CONFIG['username']}@{NAS_CONFIG['host']}", f"cat > {remote_path}"]
                process = subprocess.Popen(ssh_cmd, stdin=subprocess.PIPE)
                process.communicate(input=f.read(), timeout=30)
                if process.returncode == 0:
                    print("✅ version.json 更新成功")
                else:
                    print("❌ version.json 更新失败")
        except Exception as e:
            print(f"❌ 更新异常: {e}")
        finally:
            if temp_json.exists():
                temp_json.unlink()
        return True

    def build_ios(self):
        print("\n" + "="*50)
        print("🍎 开始构建 iOS")
        print("="*50)
        os.chdir(self.project_dir)
        os.chdir(self.project_dir / "ios")
        self.run_command(["pod", "install"], capture_output=False)
        os.chdir(self.project_dir)
        build_args = ["flutter", "build", "ios", "--release"]
        if not PROJECT_CONFIG["ios_code_sign"]:
            build_args.append("--no-codesign")
        print("🔨 构建 iOS...")
        success, output = self.run_command(build_args, capture_output=False)
        if not success:
            print("❌ iOS 构建失败")
            self.build_failed_notification("iOS", output)
            return False
        app_path = self.project_dir / "build/ios/Release-iphoneos/Runner.app"
        if not app_path.exists():
            error_msg = "找不到 Runner.app"
            print(f"❌ {error_msg}")
            self.build_failed_notification("iOS", error_msg)
            return False
        file_name = NAMING_CONFIG["pattern"].format(version=self.version, date=self.date_suffix) + f".{NAMING_CONFIG['ios_ext']}"
        ipa_path = self.project_dir / PROJECT_CONFIG["build_output_dir"] / file_name
        ipa_path.parent.mkdir(parents=True, exist_ok=True)
        payload_dir = Path(tempfile.gettempdir()) / "Payload"
        if payload_dir.exists():
            shutil.rmtree(payload_dir)
        shutil.copytree(app_path, payload_dir / "Runner.app")
        os.chdir(tempfile.gettempdir())
        self.run_command(["zip", "-r", str(ipa_path), "Payload"], capture_output=False)
        shutil.rmtree(payload_dir)
        os.chdir(self.project_dir)
        file_size = f"{ipa_path.stat().st_size / 1024 / 1024:.2f} MB"
        print(f"✅ IPA 创建成功: {file_name} ({file_size})")
        
        nas_success, nas_action = self.upload_to_nas(ipa_path, "ios", "iOS")
        github_success, github_action = self.upload_to_github_release(ipa_path, "iOS")
        
        self.build_results["iOS"] = {
            "success": True, 
            "file_name": file_name, 
            "file_size": file_size, 
            "nas_uploaded": nas_success,
            "nas_action": nas_action if nas_success else f"失败({nas_action})",
            "github_uploaded": github_success,
            "github_action": github_action if github_success else f"失败({github_action})"
        }
        return True

    def build_android(self):
        print("\n" + "="*50)
        print("🤖 开始构建 Android (ARM64)")
        print("="*50)
        os.chdir(self.project_dir)
        print("🔨 构建 APK... (可能需要几分钟)")
        build_args = ["flutter", "build", "apk", "--release", "--target-platform", PROJECT_CONFIG["android_arch"]]
        success, output = self.run_command(build_args, capture_output=False)
        if not success:
            print("❌ APK 构建失败")
            self.build_failed_notification("Android", output)
            return False
        apk_src = self.project_dir / "build/app/outputs/flutter-apk/app-release.apk"
        if not apk_src.exists():
            error_msg = "找不到 APK 文件"
            print(f"❌ {error_msg}")
            self.build_failed_notification("Android", error_msg)
            return False
        file_name = NAMING_CONFIG["pattern"].format(version=self.version, date=self.date_suffix) + f".{NAMING_CONFIG['android_ext']}"
        apk_dst = self.project_dir / PROJECT_CONFIG["build_output_dir"] / file_name
        shutil.copy(apk_src, apk_dst)
        file_size = f"{apk_dst.stat().st_size / 1024 / 1024:.2f} MB"
        print(f"✅ APK 创建成功: {file_name} ({file_size})")
        
        nas_success, nas_action = self.upload_to_nas(apk_dst, "android", "Android")
        github_success, github_action = self.upload_to_github_release(apk_dst, "Android")
        
        self.build_results["Android"] = {
            "success": True, 
            "file_name": file_name, 
            "file_size": file_size, 
            "nas_uploaded": nas_success,
            "nas_action": nas_action if nas_success else f"失败({nas_action})",
            "github_uploaded": github_success,
            "github_action": github_action if github_success else f"失败({github_action})"
        }
        return True

    def build_macos(self):
        print("\n" + "="*50)
        print("🍎 开始构建 macOS")
        print("="*50)
        os.chdir(self.project_dir)
        print("🔨 构建 macOS...")
        success, output = self.run_command(["flutter", "build", "macos", "--release"], capture_output=False)
        if not success:
            print("❌ macOS 构建失败")
            print(f"详细错误: {output}")
            self.build_failed_notification("macOS", output)
            return False
        # 查找 .app
        possible_paths = [self.project_dir / "build/macos/Build/Products/Release", self.project_dir / "build/macosx/Build/Products/Release"]
        app_path = None
        for base in possible_paths:
            if base.exists():
                for item in base.iterdir():
                    if item.suffix == ".app":
                        app_path = item
                        break
                if app_path:
                    break
        if not app_path:
            error_msg = "找不到生成的应用文件"
            print(f"❌ {error_msg}")
            self.build_failed_notification("macOS", error_msg)
            return False
        app_name = app_path.stem
        file_name = NAMING_CONFIG["pattern"].format(version=self.version, date=self.date_suffix) + f".{NAMING_CONFIG['macos_ext']}"
        output_path = self.project_dir / PROJECT_CONFIG["build_output_dir"] / file_name
        temp_dir = Path(tempfile.gettempdir()) / "fundlink_dmg_build"
        if temp_dir.exists():
            shutil.rmtree(temp_dir)
        temp_dir.mkdir()
        shutil.copytree(app_path, temp_dir / f"{app_name}.app")
        os.chdir(temp_dir)
        os.symlink("/Applications", "Applications")
        temp_dmg = Path(tempfile.gettempdir()) / "fundlink_temp.dmg"
        cmd_create = ["hdiutil", "create", "-volname", "FundLink", "-srcfolder", str(temp_dir), "-format", "UDZO", "-ov", str(temp_dmg)]
        success, _ = self.run_command(cmd_create, capture_output=False)
        if not success:
            shutil.rmtree(temp_dir)
            self.build_failed_notification("macOS", "DMG 创建失败")
            return False
        shutil.move(str(temp_dmg), str(output_path))
        shutil.rmtree(temp_dir)
        os.chdir(self.project_dir)
        file_size = f"{output_path.stat().st_size / 1024 / 1024:.2f} MB"
        print(f"✅ DMG 创建成功: {output_path.name} ({file_size})")
        
        nas_success, nas_action = self.upload_to_nas(output_path, "macos", "macOS")
        github_success, github_action = self.upload_to_github_release(output_path, "macOS")
        
        self.build_results["macOS"] = {
            "success": True, 
            "file_name": output_path.name, 
            "file_size": file_size, 
            "nas_uploaded": nas_success,
            "nas_action": nas_action if nas_success else f"失败({nas_action})",
            "github_uploaded": github_success,
            "github_action": github_action if github_success else f"失败({github_action})"
        }
        return True

    def build_windows(self):
        print("\n" + "="*50)
        print("🪟 开始构建 Windows")
        print("="*50)
        os.chdir(self.project_dir)
        print("🔨 构建 Windows...")
        success, output = self.run_command(["flutter", "build", "windows", "--release"], capture_output=False)
        if not success:
            print("❌ Windows 构建失败")
            print(f"详细错误: {output}")
            self.build_failed_notification("Windows", output)
            return False
        release_dir = self.project_dir / "build/windows/x64/runner/Release"
        if not release_dir.exists():
            error_msg = f"找不到构建输出目录: {release_dir}"
            print(f"❌ {error_msg}")
            self.build_failed_notification("Windows", error_msg)
            return False
        file_name = NAMING_CONFIG["pattern"].format(version=self.version, date=self.date_suffix) + f".{NAMING_CONFIG['windows_ext']}"
        zip_path = self.project_dir / PROJECT_CONFIG["build_output_dir"] / file_name
        zip_path.parent.mkdir(parents=True, exist_ok=True)
        print("📦 打包为 ZIP...")
        import zipfile
        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
            for file in release_dir.rglob("*"):
                if file.is_file():
                    arcname = file.relative_to(release_dir.parent)
                    zipf.write(file, arcname)
        file_size = f"{zip_path.stat().st_size / 1024 / 1024:.2f} MB"
        print(f"✅ ZIP 创建成功: {file_name} ({file_size})")
        
        nas_success, nas_action = self.upload_to_nas(zip_path, "windows", "Windows")
        github_success, github_action = self.upload_to_github_release(zip_path, "Windows")
        
        self.build_results["Windows"] = {
            "success": True, 
            "file_name": file_name, 
            "file_size": file_size, 
            "nas_uploaded": nas_success,
            "nas_action": nas_action if nas_success else f"失败({nas_action})",
            "github_uploaded": github_success,
            "github_action": github_action if github_success else f"失败({github_action})"
        }
        return True

    def run(self):
        global GITHUB_NETWORK_ERROR
        GITHUB_NETWORK_ERROR = False
        
        print("="*60)
        print("FundLink 跨平台自动打包脚本")
        print("="*60)
        print(f"当前操作系统: {self.current_os}")
        print(f"项目目录: {self.project_dir}")
        
        # 首先切换到项目目录
        os.chdir(self.project_dir)
        print(f"工作目录: {os.getcwd()}")
        
        if not validate_config():
            return False
        
        self.version = self.get_version_from_pubspec()
        if not self.version:
            error_msg = "无法从 pubspec.yaml 获取版本号"
            print(f"❌ {error_msg}")
            self.send_bark_notification("打包失败", error_msg, False)
            return False
        
        self.update_logs = self.parse_update_logs_from_dart()
        self.latest_release_notes = self.get_latest_release_notes()

        if self.current_os == "Darwin":
            platform_list = "iOS, Android, macOS"
        else:
            platform_list = "Windows, Android"

        self.send_bark_notification(
            "打包开始",
            f"版本 {self.version} 开始打包\n更新: {self.latest_release_notes[:50]}...\n平台: {platform_list}",
            success=True
        )

        print(f"版本号: {self.version}")
        print(f"版本代码: {self.version_code}")
        print(f"构建日期: {self.date_suffix}")
        print(f"最新更新: {self.latest_release_notes}")
        print(f"GitHub 上传: {'启用' if GITHUB_CONFIG['enabled'] else '禁用'}")
        print(f"NAS 上传: {'启用' if NAS_CONFIG['enabled'] else '禁用'}")

        if PROJECT_CONFIG["clean_before_build"]:
            print("\n🧹 清理构建缓存...")
            self.run_command(["flutter", "clean"], capture_output=False)
        print("\n📦 获取依赖...")
        self.run_command(["flutter", "pub", "get"], capture_output=False)

        if NAS_CONFIG["enabled"]:
            self.unlock_ssh_key()

        if self.current_os == "Darwin":
            print("\n📦 默认打包: iOS, Android, macOS")
            self.build_ios()
            self.build_android()
            self.build_macos()
        elif self.current_os == "Windows":
            print("\n📦 默认打包: Windows, Android")
            self.build_windows()
            self.build_android()

        if NAS_CONFIG["enabled"] and self.build_results:
            self.update_version_json()
        self.send_complete_notification()
        
        # 最终总结
        print("\n" + "="*60)
        print("📊 上传结果详细总结")
        print("="*60)
        print("\n【NAS 上传情况】")
        for name, result in self.build_results.items():
            if result.get("success"):
                nas_status = result.get("nas_action", "未知")
                print(f"  📁 {name}: {nas_status}")
        print("\n【GitHub Release 上传情况】")
        for name, result in self.build_results.items():
            if result.get("success"):
                github_status = result.get("github_action", "未知")
                print(f"  🐙 {name}: {github_status}")
        print("\n说明：")
        print("  - 「新上传」：目标位置不存在该文件")
        print("  - 「覆盖上传」：目标位置已有同名文件，已删除旧文件并上传新文件")
        print("  - 「新创建 Release 并上传」：首次创建 Release 并上传")
        print("  - 「覆盖上传 (已删除旧文件)」：GitHub Release 中存在同名资产，删除后重新上传")
        print("="*60)
        
        all_success = all(r.get("success") for r in self.build_results.values())
        return all_success

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--skip-nas', action='store_true', help='跳过上传到 NAS')
    parser.add_argument('--skip-github', action='store_true', help='跳过上传到 GitHub')
    parser.add_argument('--skip-bark', action='store_true', help='跳过 Bark 推送')
    parser.add_argument('--only-platform', choices=['ios', 'android', 'macos', 'windows'], help='只打包指定平台')
    args = parser.parse_args()
    if args.skip_nas:
        NAS_CONFIG["enabled"] = False
    if args.skip_github:
        GITHUB_CONFIG["enabled"] = False
    if args.skip_bark:
        BARK_CONFIG["enabled"] = False
    builder = FundLinkBuilder()
    try:
        if args.only_platform:
            platform_map = {
                'ios': builder.build_ios,
                'android': builder.build_android,
                'macos': builder.build_macos,
                'windows': builder.build_windows,
            }
            if args.only_platform in platform_map:
                success = platform_map[args.only_platform]()
            else:
                print(f"❌ 不支持的平台: {args.only_platform}")
                success = False
        else:
            success = builder.run()
    except KeyboardInterrupt:
        print("\n⚠️ 用户中断")
        success = False
    except Exception as e:
        print(f"\n❌ 脚本发生未捕获异常: {e}")
        import traceback
        traceback.print_exc()
        success = False
    finally:
        input("\n📦 打包流程结束，按回车键退出...")
        sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
#!/usr/bin/env python3
"""
WebDriverAgent 测试脚本

使用方法:
1. 确保手机上的 WDA 正在运行
2. 使用 USB 连接手机到电脑
3. 运行端口转发命令: tidevice relay 8100 8100
4. 运行此脚本: python wda_test.py

注意事项:
- WDA 是一个 XCTest Bundle，不能像普通 App 一样直接运行
- 需要通过 Xcode、tidevice、或 libimobiledevice 启动 WDA
- 推荐使用: tidevice wdaproxy -B <WDA_BUNDLE_ID> --port 8100
"""

import requests
import time
import json
import sys
import base64
from datetime import datetime


class WDAClient:
    """WebDriverAgent 客户端"""

    def __init__(self, url="http://localhost:8100"):
        self.base_url = url.rstrip("/")
        self.session_id = None

    def check_status(self):
        """检查 WDA 状态"""
        try:
            resp = requests.get(f"{self.base_url}/status", timeout=5)
            if resp.status_code == 200:
                data = resp.json()
                print("✅ WDA 连接成功!")
                print(f"   IP: {data.get('value', {}).get('ios', {}).get('ip', 'N/A')}")
                print(f"   设备名: {data.get('value', {}).get('ios', {}).get('deviceName', 'N/A')}")
                print(f"   iOS版本: {data.get('value', {}).get('os', {}).get('version', 'N/A')}")
                return True
            else:
                print(f"❌ WDA 返回错误: {resp.status_code}")
                return False
        except requests.exceptions.ConnectionError:
            print(f"❌ 无法连接到 {self.base_url}")
            print("   请确保:")
            print("   1. WDA 已在 iPhone 上启动")
            print("   2. 端口转发已运行: tidevice relay 8100 8100")
            return False
        except Exception as e:
            print(f"❌ 连接错误: {e}")
            return False

    def create_session(self, bundle_id="com.apple.Preferences"):
        """创建新会话 (启动应用)"""
        payload = {
            "capabilities": {
                "bundleId": bundle_id,
                "shouldWaitForQuiescence": False
            }
        }
        try:
            resp = requests.post(f"{self.base_url}/session", json=payload, timeout=30)
            if resp.status_code == 200:
                data = resp.json()
                self.session_id = data.get("sessionId") or data.get("value", {}).get("sessionId")
                print(f"✅ 会话创建成功: {self.session_id}")
                print(f"   启动应用: {bundle_id}")
                return True
            else:
                print(f"❌ 创建会话失败: {resp.text}")
                return False
        except Exception as e:
            print(f"❌ 创建会话错误: {e}")
            return False

    def get_window_size(self):
        """获取屏幕尺寸"""
        try:
            resp = requests.get(f"{self.base_url}/session/{self.session_id}/window/size", timeout=5)
            if resp.status_code == 200:
                size = resp.json().get("value", {})
                print(f"📱 屏幕尺寸: {size.get('width')} x {size.get('height')}")
                return size
        except Exception as e:
            print(f"❌ 获取尺寸失败: {e}")
        return None

    def tap(self, x, y):
        """点击指定坐标"""
        payload = {"x": x, "y": y}
        try:
            resp = requests.post(
                f"{self.base_url}/session/{self.session_id}/wda/tap/0",
                json=payload,
                timeout=10
            )
            if resp.status_code == 200:
                print(f"👆 点击成功: ({x}, {y})")
                return True
            else:
                print(f"❌ 点击失败: {resp.text}")
                return False
        except Exception as e:
            print(f"❌ 点击错误: {e}")
            return False

    def swipe(self, from_x, from_y, to_x, to_y, duration=0.5):
        """滑动操作"""
        payload = {
            "fromX": from_x,
            "fromY": from_y,
            "toX": to_x,
            "toY": to_y,
            "duration": duration
        }
        try:
            resp = requests.post(
                f"{self.base_url}/session/{self.session_id}/wda/dragfromtoforduration",
                json=payload,
                timeout=10
            )
            if resp.status_code == 200:
                print(f"👉 滑动成功: ({from_x},{from_y}) -> ({to_x},{to_y})")
                return True
            else:
                print(f"❌ 滑动失败: {resp.text}")
                return False
        except Exception as e:
            print(f"❌ 滑动错误: {e}")
            return False

    def screenshot(self, save_path=None):
        """截屏"""
        try:
            resp = requests.get(f"{self.base_url}/screenshot", timeout=10)
            if resp.status_code == 200:
                data = resp.json()
                img_base64 = data.get("value", "")
                if img_base64:
                    if save_path is None:
                        save_path = f"screenshot_{datetime.now().strftime('%Y%m%d_%H%M%S')}.png"
                    with open(save_path, "wb") as f:
                        f.write(base64.b64decode(img_base64))
                    print(f"📷 截图已保存: {save_path}")
                    return save_path
            else:
                print(f"❌ 截屏失败: {resp.status_code}")
        except Exception as e:
            print(f"❌ 截屏错误: {e}")
        return None

    def home(self):
        """按 Home 键"""
        try:
            resp = requests.post(f"{self.base_url}/wda/homescreen", timeout=5)
            if resp.status_code == 200:
                print("🏠 已返回主屏幕")
                return True
        except Exception as e:
            print(f"❌ Home 键操作失败: {e}")
        return False

    def get_source(self):
        """获取当前屏幕 UI 元素树"""
        try:
            resp = requests.get(f"{self.base_url}/source", timeout=30)
            if resp.status_code == 200:
                source = resp.json().get("value", "")
                print("📄 已获取页面源码")
                return source
        except Exception as e:
            print(f"❌ 获取源码失败: {e}")
        return None

    def find_element(self, using="accessibility id", value=""):
        """查找元素"""
        payload = {"using": using, "value": value}
        try:
            resp = requests.post(
                f"{self.base_url}/session/{self.session_id}/element",
                json=payload,
                timeout=10
            )
            if resp.status_code == 200:
                element = resp.json().get("value", {})
                element_id = element.get("ELEMENT")
                print(f"🔍 找到元素: {element_id}")
                return element_id
        except Exception as e:
            print(f"❌ 查找元素失败: {e}")
        return None

    def click_element(self, element_id):
        """点击元素"""
        try:
            resp = requests.post(
                f"{self.base_url}/session/{self.session_id}/element/{element_id}/click",
                timeout=10
            )
            if resp.status_code == 200:
                print(f"👆 元素点击成功")
                return True
        except Exception as e:
            print(f"❌ 点击元素失败: {e}")
        return False


def main():
    print("=" * 50)
    print("WebDriverAgent 测试脚本")
    print("=" * 50)
    print()

    # 尝试连接
    client = WDAClient("http://localhost:8100")

    print("🔄 检查 WDA 连接状态...")
    if not client.check_status():
        print()
        print("=" * 50)
        print("🛠️ 启动 WDA 的方法:")
        print("=" * 50)
        print()
        print("方法1: 使用 tidevice (推荐)")
        print("  pip install tidevice")
        print("  tidevice wdaproxy -B <WDA_BUNDLE_ID> --port 8100")
        print("  # WDA_BUNDLE_ID 通常是: com.xxx.WebDriverAgentRunner.xctrunner")
        print()
        print("方法2: 使用 Xcode")
        print("  在 Xcode 中打开 WDA 项目，选择真机，按 Cmd+U 运行测试")
        print()
        print("方法3: 仅端口转发 (WDA 已在手机后台)")
        print("  tidevice relay 8100 8100")
        print()
        sys.exit(1)

    print()
    print("=" * 50)
    print("🚀 开始功能测试")
    print("=" * 50)
    print()

    # 创建会话 (启动设置应用)
    print("📱 启动 '设置' 应用...")
    if not client.create_session("com.apple.Preferences"):
        print("无法创建会话，退出")
        sys.exit(1)

    time.sleep(2)

    # 获取屏幕尺寸
    size = client.get_window_size()

    # 截屏
    client.screenshot()

    if size:
        width = size.get("width", 390)
        height = size.get("height", 844)

        # 向下滑动
        print()
        print("📜 演示: 向下滑动...")
        client.swipe(width // 2, height // 2, width // 2, height // 4, duration=0.3)
        time.sleep(1)

        # 向上滑动
        print("📜 演示: 向上滑动...")
        client.swipe(width // 2, height // 4, width // 2, height // 2, duration=0.3)
        time.sleep(1)

    # 再次截屏
    client.screenshot("after_swipe.png")

    # 返回主屏幕
    print()
    print("🏠 返回主屏幕...")
    client.home()

    print()
    print("=" * 50)
    print("✅ 测试完成!")
    print("=" * 50)


if __name__ == "__main__":
    main()

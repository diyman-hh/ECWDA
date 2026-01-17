#!/usr/bin/env python3
"""
ECWDA Python SDK
增强版 WebDriverAgent Python 客户端
"""

import requests
import base64
import time
import json
from typing import Optional, Dict, List, Tuple, Any


class ECWDA:
    """ECWDA 客户端类"""
    
    def __init__(self, url: str = "http://localhost:8100"):
        """
        初始化 ECWDA 客户端
        
        Args:
            url: WDA 服务地址，默认 http://localhost:8100
        """
        self.base_url = url.rstrip("/")
        self.session_id: Optional[str] = None
        self.screen_width: int = 375
        self.screen_height: int = 667
        self.timeout: int = 10
        
    def is_connected(self) -> bool:
        """
        检查连接状态
        
        Returns:
            bool: 是否连接成功
        """
        try:
            resp = requests.get(f"{self.base_url}/status", timeout=5)
            return resp.status_code == 200
        except:
            return False
    
    def create_session(self, bundle_id: str = "com.apple.Preferences") -> bool:
        """
        创建会话
        
        Args:
            bundle_id: 要启动的应用 Bundle ID
            
        Returns:
            bool: 是否成功
        """
        try:
            resp = requests.post(
                f"{self.base_url}/session",
                json={
                    "capabilities": {
                        "bundleId": bundle_id
                    }
                },
                timeout=self.timeout
            )
            data = resp.json()
            self.session_id = data.get("sessionId")
            
            # 获取屏幕尺寸
            if self.session_id:
                self._update_screen_size()
                
            return self.session_id is not None
        except Exception as e:
            print(f"创建会话失败: {e}")
            return False
    
    def _update_screen_size(self):
        """更新屏幕尺寸"""
        try:
            resp = requests.get(
                f"{self.base_url}/session/{self.session_id}/window/size",
                timeout=5
            )
            data = resp.json()
            if "value" in data:
                self.screen_width = data["value"].get("width", 375)
                self.screen_height = data["value"].get("height", 667)
        except:
            pass
    
    def _ensure_session(self):
        """确保会话存在"""
        if not self.session_id:
            self.create_session()
    
    # ========== 点击函数 ==========
    
    def click(self, x: int, y: int) -> bool:
        """
        点击指定坐标
        
        Args:
            x: X 坐标
            y: Y 坐标
            
        Returns:
            bool: 是否成功
        """
        self._ensure_session()
        try:
            resp = requests.post(
                f"{self.base_url}/session/{self.session_id}/wda/tap/0",
                json={"x": x, "y": y},
                timeout=self.timeout
            )
            return resp.status_code == 200
        except:
            return False
    
    def long_click(self, x: int, y: int, duration: float = 1.0) -> bool:
        """
        长按指定坐标
        
        Args:
            x: X 坐标
            y: Y 坐标
            duration: 长按时间（秒）
            
        Returns:
            bool: 是否成功
        """
        self._ensure_session()
        try:
            resp = requests.post(
                f"{self.base_url}/session/{self.session_id}/wda/touchAndHold",
                json={"x": x, "y": y, "duration": duration},
                timeout=self.timeout + duration
            )
            return resp.status_code == 200
        except:
            return False
    
    def double_click(self, x: int, y: int) -> bool:
        """
        双击指定坐标
        
        Args:
            x: X 坐标
            y: Y 坐标
            
        Returns:
            bool: 是否成功
        """
        self._ensure_session()
        try:
            resp = requests.post(
                f"{self.base_url}/session/{self.session_id}/wda/doubleTap",
                json={"x": x, "y": y},
                timeout=self.timeout
            )
            return resp.status_code == 200
        except:
            return False
    
    # ========== 滑动函数 ==========
    
    def swipe(self, from_x: int, from_y: int, to_x: int, to_y: int, 
              duration: float = 0.5) -> bool:
        """
        滑动操作
        
        Args:
            from_x: 起始 X 坐标
            from_y: 起始 Y 坐标
            to_x: 结束 X 坐标
            to_y: 结束 Y 坐标
            duration: 滑动时间（秒）
            
        Returns:
            bool: 是否成功
        """
        self._ensure_session()
        try:
            resp = requests.post(
                f"{self.base_url}/session/{self.session_id}/wda/dragFromToForDuration",
                json={
                    "fromX": from_x,
                    "fromY": from_y,
                    "toX": to_x,
                    "toY": to_y,
                    "duration": duration
                },
                timeout=self.timeout + duration
            )
            return resp.status_code == 200
        except:
            return False
    
    def swipe_up(self, duration: float = 0.5) -> bool:
        """向上滑动"""
        cx = self.screen_width // 2
        return self.swipe(cx, int(self.screen_height * 0.7), 
                         cx, int(self.screen_height * 0.3), duration)
    
    def swipe_down(self, duration: float = 0.5) -> bool:
        """向下滑动"""
        cx = self.screen_width // 2
        return self.swipe(cx, int(self.screen_height * 0.3), 
                         cx, int(self.screen_height * 0.7), duration)
    
    def swipe_left(self, duration: float = 0.5) -> bool:
        """向左滑动"""
        cy = self.screen_height // 2
        return self.swipe(int(self.screen_width * 0.8), cy,
                         int(self.screen_width * 0.2), cy, duration)
    
    def swipe_right(self, duration: float = 0.5) -> bool:
        """向右滑动"""
        cy = self.screen_height // 2
        return self.swipe(int(self.screen_width * 0.2), cy,
                         int(self.screen_width * 0.8), cy, duration)
    
    # ========== 截图函数 ==========
    
    def screenshot(self, save_path: Optional[str] = None) -> Optional[str]:
        """
        截取屏幕截图
        
        Args:
            save_path: 保存路径，不传则返回 base64
            
        Returns:
            str: Base64 编码的图片或保存路径
        """
        try:
            resp = requests.get(f"{self.base_url}/screenshot", timeout=self.timeout)
            data = resp.json()
            
            if "value" in data:
                img_base64 = data["value"]
                
                if save_path:
                    img_data = base64.b64decode(img_base64)
                    with open(save_path, "wb") as f:
                        f.write(img_data)
                    return save_path
                else:
                    return img_base64
        except Exception as e:
            print(f"截图失败: {e}")
        return None
    
    # ========== 图色函数 ==========
    
    def get_pixel_color(self, x: int, y: int) -> Optional[str]:
        """
        获取指定坐标的颜色
        
        Args:
            x: X 坐标
            y: Y 坐标
            
        Returns:
            str: 颜色值，如 "#FF5500"
        """
        try:
            # 截图并获取像素颜色
            img_base64 = self.screenshot()
            if not img_base64:
                return None
            
            from PIL import Image
            import io
            
            img_data = base64.b64decode(img_base64)
            img = Image.open(io.BytesIO(img_data))
            
            # 获取像素
            pixel = img.getpixel((x, y))
            if len(pixel) >= 3:
                return f"#{pixel[0]:02X}{pixel[1]:02X}{pixel[2]:02X}"
        except Exception as e:
            print(f"获取颜色失败: {e}")
        return None
    
    def find_color(self, color: str, region: Optional[Dict] = None, 
                   tolerance: int = 10) -> Optional[Dict[str, int]]:
        """
        在屏幕中查找指定颜色
        
        Args:
            color: 颜色值，如 "#FF5500"
            region: 查找区域 {"x": 0, "y": 0, "width": 375, "height": 667}
            tolerance: 容差值
            
        Returns:
            dict: 找到返回 {"x": 100, "y": 200}，否则返回 None
        """
        try:
            from PIL import Image
            import io
            
            # 截图
            img_base64 = self.screenshot()
            if not img_base64:
                return None
            
            img_data = base64.b64decode(img_base64)
            img = Image.open(io.BytesIO(img_data)).convert("RGB")
            
            # 解析目标颜色
            target_color = self._parse_color(color)
            if not target_color:
                return None
            
            # 设置搜索区域
            if region:
                x_start = region.get("x", 0)
                y_start = region.get("y", 0)
                x_end = x_start + region.get("width", img.width)
                y_end = y_start + region.get("height", img.height)
            else:
                x_start, y_start = 0, 0
                x_end, y_end = img.width, img.height
            
            # 遍历像素查找
            for y in range(y_start, min(y_end, img.height)):
                for x in range(x_start, min(x_end, img.width)):
                    pixel = img.getpixel((x, y))
                    if self._color_match(pixel, target_color, tolerance):
                        return {"x": x, "y": y}
            
            return None
        except Exception as e:
            print(f"找色失败: {e}")
            return None
    
    def find_multi_color(self, first_color: str, offset_colors: List[Dict],
                         region: Optional[Dict] = None, 
                         tolerance: int = 10) -> Optional[Dict[str, int]]:
        """
        多点找色
        
        Args:
            first_color: 第一个颜色
            offset_colors: 偏移颜色列表 [{"offset": [10, 0], "color": "#00FF00"}]
            region: 查找区域
            tolerance: 容差值
            
        Returns:
            dict: 找到返回第一个颜色的坐标
        """
        try:
            from PIL import Image
            import io
            
            # 截图
            img_base64 = self.screenshot()
            if not img_base64:
                return None
            
            img_data = base64.b64decode(img_base64)
            img = Image.open(io.BytesIO(img_data)).convert("RGB")
            
            # 解析第一个颜色
            target_color = self._parse_color(first_color)
            if not target_color:
                return None
            
            # 解析偏移颜色
            parsed_offsets = []
            for oc in offset_colors:
                c = self._parse_color(oc["color"])
                if c:
                    parsed_offsets.append({
                        "offset": oc["offset"],
                        "color": c
                    })
            
            # 设置搜索区域
            if region:
                x_start = region.get("x", 0)
                y_start = region.get("y", 0)
                x_end = x_start + region.get("width", img.width)
                y_end = y_start + region.get("height", img.height)
            else:
                x_start, y_start = 0, 0
                x_end, y_end = img.width, img.height
            
            # 遍历查找
            for y in range(y_start, min(y_end, img.height)):
                for x in range(x_start, min(x_end, img.width)):
                    pixel = img.getpixel((x, y))
                    
                    # 检查第一个颜色
                    if not self._color_match(pixel, target_color, tolerance):
                        continue
                    
                    # 检查所有偏移颜色
                    all_match = True
                    for oc in parsed_offsets:
                        ox = x + oc["offset"][0]
                        oy = y + oc["offset"][1]
                        
                        if ox < 0 or ox >= img.width or oy < 0 or oy >= img.height:
                            all_match = False
                            break
                        
                        offset_pixel = img.getpixel((ox, oy))
                        if not self._color_match(offset_pixel, oc["color"], tolerance):
                            all_match = False
                            break
                    
                    if all_match:
                        return {"x": x, "y": y}
            
            return None
        except Exception as e:
            print(f"多点找色失败: {e}")
            return None
    
    def cmp_color(self, x: int, y: int, color: str, tolerance: int = 10) -> bool:
        """
        比较指定坐标的颜色
        
        Args:
            x: X 坐标
            y: Y 坐标
            color: 目标颜色
            tolerance: 容差值
            
        Returns:
            bool: 是否匹配
        """
        actual_color = self.get_pixel_color(x, y)
        if not actual_color:
            return False
        
        target = self._parse_color(color)
        actual = self._parse_color(actual_color)
        
        if target and actual:
            return self._color_match(actual, target, tolerance)
        return False
    
    def _parse_color(self, color: str) -> Optional[Tuple[int, int, int]]:
        """解析颜色字符串"""
        try:
            color = color.lstrip("#")
            if len(color) == 6:
                return (
                    int(color[0:2], 16),
                    int(color[2:4], 16),
                    int(color[4:6], 16)
                )
        except:
            pass
        return None
    
    def _color_match(self, c1: Tuple, c2: Tuple, tolerance: int) -> bool:
        """检查颜色是否匹配"""
        return (abs(c1[0] - c2[0]) <= tolerance and
                abs(c1[1] - c2[1]) <= tolerance and
                abs(c1[2] - c2[2]) <= tolerance)
    
    # ========== OCR 函数 ==========
    
    def ocr(self, region: Optional[Dict] = None) -> List[Dict]:
        """
        OCR 文字识别（需要服务端支持）
        
        Args:
            region: 识别区域
            
        Returns:
            list: 识别结果 [{"text": "设置", "x": 100, "y": 200}]
        """
        # TODO: 需要在 WDA 中添加 OCR 支持
        # 目前返回空列表
        return []
    
    def find_text(self, text: str, region: Optional[Dict] = None) -> Optional[Dict[str, int]]:
        """
        查找文字位置
        
        Args:
            text: 要查找的文字
            region: 查找区域
            
        Returns:
            dict: 找到返回坐标
        """
        results = self.ocr(region)
        for item in results:
            if text in item.get("text", ""):
                return {"x": item["x"], "y": item["y"]}
        return None
    
    # ========== 设备函数 ==========
    
    def get_device_info(self) -> Dict[str, Any]:
        """
        获取设备信息
        
        Returns:
            dict: 设备信息
        """
        info = {
            "name": "Unknown",
            "os_version": "Unknown",
            "screen_width": self.screen_width,
            "screen_height": self.screen_height,
            "battery": 100
        }
        
        try:
            resp = requests.get(f"{self.base_url}/status", timeout=5)
            data = resp.json()
            
            if "value" in data:
                value = data["value"]
                info["os_version"] = value.get("ios", {}).get("sdkVersion", "Unknown")
                info["name"] = value.get("ios", {}).get("name", "Unknown")
        except:
            pass
        
        return info
    
    def get_screen_size(self) -> Tuple[int, int]:
        """
        获取屏幕尺寸
        
        Returns:
            tuple: (width, height)
        """
        self._ensure_session()
        self._update_screen_size()
        return (self.screen_width, self.screen_height)
    
    # ========== 应用管理 ==========
    
    def launch_app(self, bundle_id: str) -> bool:
        """
        启动应用
        
        Args:
            bundle_id: 应用的 Bundle ID
            
        Returns:
            bool: 是否成功
        """
        self._ensure_session()
        try:
            resp = requests.post(
                f"{self.base_url}/session/{self.session_id}/wda/apps/launch",
                json={"bundleId": bundle_id},
                timeout=self.timeout
            )
            return resp.status_code == 200
        except:
            return False
    
    def terminate_app(self, bundle_id: str) -> bool:
        """
        关闭应用
        
        Args:
            bundle_id: 应用的 Bundle ID
            
        Returns:
            bool: 是否成功
        """
        self._ensure_session()
        try:
            resp = requests.post(
                f"{self.base_url}/session/{self.session_id}/wda/apps/terminate",
                json={"bundleId": bundle_id},
                timeout=self.timeout
            )
            return resp.status_code == 200
        except:
            return False
    
    def home(self) -> bool:
        """
        返回主屏幕
        
        Returns:
            bool: 是否成功
        """
        try:
            resp = requests.post(
                f"{self.base_url}/wda/homescreen",
                timeout=self.timeout
            )
            return resp.status_code == 200
        except:
            return False
    
    # ========== 辅助函数 ==========
    
    def sleep(self, seconds: float):
        """
        等待
        
        Args:
            seconds: 等待秒数
        """
        time.sleep(seconds)
    
    def wait_color(self, color: str, region: Optional[Dict] = None,
                   timeout: float = 10, interval: float = 0.5) -> Optional[Dict[str, int]]:
        """
        等待颜色出现
        
        Args:
            color: 目标颜色
            region: 查找区域
            timeout: 超时时间
            interval: 检查间隔
            
        Returns:
            dict: 找到返回坐标
        """
        start_time = time.time()
        while time.time() - start_time < timeout:
            pos = self.find_color(color, region)
            if pos:
                return pos
            time.sleep(interval)
        return None
    
    # ========== 脱机脚本执行 ==========
    
    def execute_script(self, commands: List[Dict], script_id: Optional[str] = None) -> Dict:
        """
        执行脚本 (脱机模式)
        
        Args:
            commands: 命令列表
            script_id: 脚本 ID
            
        Returns:
            dict: 执行结果
        """
        try:
            payload = {"commands": commands}
            if script_id:
                payload["scriptId"] = script_id
                
            resp = requests.post(
                f"{self.base_url}/wda/script/execute",
                json=payload,
                timeout=self.timeout
            )
            return resp.json().get("value", {})
        except Exception as e:
            return {"error": str(e)}
    
    def get_script_status(self) -> Dict:
        """
        获取脚本执行状态
        
        Returns:
            dict: 状态信息
        """
        try:
            resp = requests.get(
                f"{self.base_url}/wda/script/status",
                timeout=self.timeout
            )
            return resp.json().get("value", {})
        except Exception as e:
            return {"error": str(e)}
    
    def stop_script(self) -> bool:
        """
        停止脚本执行
        
        Returns:
            bool: 是否成功
        """
        try:
            resp = requests.post(
                f"{self.base_url}/wda/script/stop",
                timeout=self.timeout
            )
            return resp.status_code == 200
        except:
            return False
    
    # ========== 扩展 API (需要 ECWDA 扩展) ==========
    
    def find_color_native(self, color: str, region: Optional[Dict] = None, 
                          tolerance: int = 10) -> Optional[Dict[str, int]]:
        """
        找色 (使用原生 API，更快)
        
        Args:
            color: 颜色值
            region: 查找区域
            tolerance: 容差值
            
        Returns:
            dict: 找到返回坐标
        """
        try:
            payload = {"color": color, "tolerance": tolerance}
            if region:
                payload["region"] = region
            
            resp = requests.post(
                f"{self.base_url}/wda/findColor",
                json=payload,
                timeout=self.timeout
            )
            data = resp.json().get("value", {})
            if data.get("found"):
                return {"x": data["x"], "y": data["y"]}
        except:
            pass
        return None
    
    def get_pixel_native(self, x: int, y: int) -> Optional[Dict]:
        """
        获取像素颜色 (使用原生 API)
        
        Args:
            x: X 坐标
            y: Y 坐标
            
        Returns:
            dict: 颜色信息
        """
        try:
            resp = requests.post(
                f"{self.base_url}/wda/pixel",
                json={"x": x, "y": y},
                timeout=self.timeout
            )
            return resp.json().get("value", {})
        except:
            return None
    
    def ocr_native(self, region: Optional[Dict] = None) -> List[Dict]:
        """
        OCR 文字识别 (使用原生 API)
        
        Args:
            region: 识别区域
            
        Returns:
            list: 识别结果
        """
        try:
            payload = {}
            if region:
                payload["region"] = region
            
            resp = requests.post(
                f"{self.base_url}/wda/ocr/recognize",
                json=payload,
                timeout=30  # OCR 可能需要更长时间
            )
            data = resp.json().get("value", {})
            return data.get("texts", [])
        except:
            return []
    
    # ========== Phase 2: 找图功能 ==========
    
    def find_image(self, template_path: str, region: Optional[Dict] = None,
                   threshold: float = 0.9) -> Optional[Dict]:
        """
        找图 (使用原生 API)
        
        Args:
            template_path: 模板图片路径
            region: 查找区域
            threshold: 匹配阈值 (0-1)
            
        Returns:
            dict: 找到返回 {"x", "y", "width", "height"}
        """
        try:
            # 读取模板图片并转为 base64
            with open(template_path, "rb") as f:
                template_base64 = base64.b64encode(f.read()).decode()
            
            payload = {"template": template_base64, "threshold": threshold}
            if region:
                payload["region"] = region
            
            resp = requests.post(
                f"{self.base_url}/wda/findImage",
                json=payload,
                timeout=30
            )
            data = resp.json().get("value", {})
            if data.get("found"):
                return {
                    "x": data["x"],
                    "y": data["y"],
                    "width": data["width"],
                    "height": data["height"]
                }
        except Exception as e:
            print(f"找图失败: {e}")
        return None
    
    def click_image(self, template_path: str, region: Optional[Dict] = None,
                    threshold: float = 0.9) -> bool:
        """
        点击找到的图片
        
        Args:
            template_path: 模板图片路径
            region: 查找区域
            threshold: 匹配阈值
            
        Returns:
            bool: 是否成功
        """
        pos = self.find_image(template_path, region, threshold)
        if pos:
            center_x = pos["x"] + pos["width"] // 2
            center_y = pos["y"] + pos["height"] // 2
            return self.click(center_x, center_y)
        return False
    
    # ========== Phase 2: 二维码识别 ==========
    
    def decode_qrcode(self, region: Optional[Dict] = None) -> List[Dict]:
        """
        识别屏幕上的二维码
        
        Args:
            region: 识别区域
            
        Returns:
            list: 二维码列表 [{"text": "...", "x", "y", "width", "height"}]
        """
        try:
            payload = {}
            if region:
                payload["region"] = region
            
            resp = requests.post(
                f"{self.base_url}/wda/qrcode/decode",
                json=payload,
                timeout=30
            )
            data = resp.json().get("value", {})
            return data.get("codes", [])
        except:
            return []
    
    # ========== Phase 2: 剪贴板 ==========
    
    def get_clipboard(self) -> str:
        """
        获取剪贴板内容
        
        Returns:
            str: 剪贴板文本
        """
        try:
            resp = requests.get(
                f"{self.base_url}/wda/clipboard",
                timeout=self.timeout
            )
            return resp.json().get("value", {}).get("content", "")
        except:
            return ""
    
    def set_clipboard(self, content: str) -> bool:
        """
        设置剪贴板内容
        
        Args:
            content: 文本内容
            
        Returns:
            bool: 是否成功
        """
        try:
            resp = requests.post(
                f"{self.base_url}/wda/clipboard",
                json={"content": content},
                timeout=self.timeout
            )
            return resp.status_code == 200
        except:
            return False
    
    # ========== Phase 2: 文件操作 ==========
    
    def get_sandbox_path(self) -> Dict[str, str]:
        """
        获取沙盒目录路径
        
        Returns:
            dict: {"documents", "caches", "tmp"}
        """
        try:
            resp = requests.get(
                f"{self.base_url}/wda/file/sandbox",
                timeout=self.timeout
            )
            return resp.json().get("value", {})
        except:
            return {}
    
    def read_file(self, path: str) -> Optional[str]:
        """
        读取文件
        
        Args:
            path: 文件路径
            
        Returns:
            str: 文件内容
        """
        try:
            resp = requests.post(
                f"{self.base_url}/wda/file/read",
                json={"path": path},
                timeout=self.timeout
            )
            return resp.json().get("value", {}).get("content")
        except:
            return None
    
    def write_file(self, path: str, content: str) -> bool:
        """
        写入文件
        
        Args:
            path: 文件路径
            content: 内容
            
        Returns:
            bool: 是否成功
        """
        try:
            resp = requests.post(
                f"{self.base_url}/wda/file/write",
                json={"path": path, "content": content},
                timeout=self.timeout
            )
            return resp.json().get("value", {}).get("success", False)
        except:
            return False
    
    def list_files(self, path: str) -> List[Dict]:
        """
        列出目录内容
        
        Args:
            path: 目录路径
            
        Returns:
            list: 文件列表
        """
        try:
            resp = requests.post(
                f"{self.base_url}/wda/file/list",
                json={"path": path},
                timeout=self.timeout
            )
            return resp.json().get("value", {}).get("files", [])
        except:
            return []
    
    def delete_file(self, path: str) -> bool:
        """
        删除文件
        
        Args:
            path: 文件路径
            
        Returns:
            bool: 是否成功
        """
        try:
            resp = requests.post(
                f"{self.base_url}/wda/file/delete",
                json={"path": path},
                timeout=self.timeout
            )
            return resp.json().get("value", {}).get("success", False)
        except:
            return False
    
    # ========== Phase 2: 文本输入 ==========
    
    def input_text(self, text: str) -> bool:
        """
        输入文本（需要先点击输入框）
        
        Args:
            text: 文本内容
            
        Returns:
            bool: 是否成功
        """
        try:
            resp = requests.post(
                f"{self.base_url}/wda/inputText",
                json={"text": text},
                timeout=self.timeout
            )
            return resp.status_code == 200
        except:
            return False
    
    # ========== Phase 2: 打开 URL ==========
    
    def open_url(self, url: str) -> bool:
        """
        打开 URL（跳转到浏览器或 App）
        
        Args:
            url: URL 地址
            
        Returns:
            bool: 是否成功
        """
        try:
            resp = requests.post(
                f"{self.base_url}/wda/openUrl",
                json={"url": url},
                timeout=self.timeout
            )
            return resp.status_code == 200
        except:
            return False


# 便捷函数
def connect(url: str = "http://localhost:8100") -> ECWDA:
    """
    连接设备
    
    Args:
        url: WDA 服务地址
        
    Returns:
        ECWDA: 客户端实例
    """
    return ECWDA(url)


if __name__ == "__main__":
    # 测试代码
    print("=" * 50)
    print("ECWDA Python SDK 测试")
    print("=" * 50)
    
    ec = ECWDA()
    
    if ec.is_connected():
        print("✅ 连接成功!")
        
        # 获取设备信息
        info = ec.get_device_info()
        print(f"设备: {info['name']}")
        print(f"iOS: {info['os_version']}")
        
        # 获取屏幕尺寸
        width, height = ec.get_screen_size()
        print(f"屏幕: {width}x{height}")
        
        # 截图
        ec.screenshot("test_screenshot.png")
        print("📷 截图已保存")
        
    else:
        print("❌ 连接失败!")
        print("请确保 WDA 正在运行，并执行: tidevice relay 8100 8100")

#!/usr/bin/env python3
"""
iOS 投屏控制工具 v2.0
优化版 - 减少闪烁，提高响应速度
"""

import tkinter as tk
from tkinter import ttk, messagebox
from PIL import Image, ImageTk
import requests
import io
import base64
import threading
import time
from concurrent.futures import ThreadPoolExecutor


class iOSScreenMirror:
    def __init__(self, wda_url="http://192.168.110.171:8100"):
        self.wda_url = wda_url.rstrip("/")
        self.session_id = None
        self.running = False
        self.screen_width = 375
        self.screen_height = 667
        self.scale = 1.5  # 显示缩放比例
        
        # 拖动状态
        self.drag_start = None
        self.drag_moved = False
        
        # 线程池用于异步操作
        self.executor = ThreadPoolExecutor(max_workers=3)
        
        # 当前图片缓存
        self.current_photo = None
        self.next_photo = None
        
        # 创建窗口
        self.root = tk.Tk()
        self.root.title("iOS 投屏控制 v2.0")
        self.root.resizable(True, True)
        
        self._setup_ui()
        self._bind_events()
        
    def _setup_ui(self):
        """设置界面"""
        # 顶部控制栏
        control_frame = ttk.Frame(self.root)
        control_frame.pack(fill=tk.X, padx=5, pady=5)
        
        # URL 输入
        ttk.Label(control_frame, text="WDA地址:").pack(side=tk.LEFT)
        self.url_entry = ttk.Entry(control_frame, width=25)
        self.url_entry.insert(0, self.wda_url)
        self.url_entry.pack(side=tk.LEFT, padx=5)
        
        # 连接按钮
        self.connect_btn = ttk.Button(control_frame, text="连接", command=self._connect)
        self.connect_btn.pack(side=tk.LEFT, padx=5)
        
        # 刷新率
        ttk.Label(control_frame, text="FPS:").pack(side=tk.LEFT, padx=(10, 0))
        self.fps_var = tk.StringVar(value="10")
        fps_combo = ttk.Combobox(control_frame, textvariable=self.fps_var, 
                                  values=["5", "10", "15", "20", "30"], width=4)
        fps_combo.pack(side=tk.LEFT, padx=2)
        
        # 缩放
        ttk.Label(control_frame, text="缩放:").pack(side=tk.LEFT, padx=(10, 0))
        self.scale_var = tk.StringVar(value="1.5")
        scale_combo = ttk.Combobox(control_frame, textvariable=self.scale_var,
                                    values=["1.0", "1.25", "1.5", "2.0"], width=4)
        scale_combo.pack(side=tk.LEFT, padx=2)
        scale_combo.bind("<<ComboboxSelected>>", self._on_scale_change)
        
        # Home 按钮
        self.home_btn = ttk.Button(control_frame, text="🏠", command=self._press_home, 
                                    state=tk.DISABLED, width=3)
        self.home_btn.pack(side=tk.LEFT, padx=5)
        
        # 截图按钮
        self.screenshot_btn = ttk.Button(control_frame, text="📷", command=self._save_screenshot, 
                                          state=tk.DISABLED, width=3)
        self.screenshot_btn.pack(side=tk.LEFT, padx=2)
        
        # 状态栏
        self.status_var = tk.StringVar(value="未连接 | 点击画面可操作手机")
        status_bar = ttk.Label(self.root, textvariable=self.status_var, relief=tk.SUNKEN)
        status_bar.pack(fill=tk.X, side=tk.BOTTOM, padx=5, pady=2)
        
        # 屏幕显示区域 - 使用 Label 代替 Canvas 减少闪烁
        self.screen_label = tk.Label(
            self.root,
            width=int(self.screen_width * self.scale),
            height=int(self.screen_height * self.scale),
            bg="black"
        )
        self.screen_label.pack(padx=5, pady=5)
        
        # 创建初始黑色图片
        self._create_placeholder()
        
    def _create_placeholder(self):
        """创建占位图"""
        w = int(self.screen_width * self.scale)
        h = int(self.screen_height * self.scale)
        img = Image.new('RGB', (w, h), color='black')
        self.current_photo = ImageTk.PhotoImage(img)
        self.screen_label.config(image=self.current_photo)
        
    def _bind_events(self):
        """绑定事件"""
        self.screen_label.bind("<Button-1>", self._on_mouse_down)
        self.screen_label.bind("<ButtonRelease-1>", self._on_mouse_up)
        self.screen_label.bind("<B1-Motion>", self._on_mouse_move)
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)
        
    def _on_scale_change(self, event=None):
        """缩放变化"""
        self.scale = float(self.scale_var.get())
        w = int(self.screen_width * self.scale)
        h = int(self.screen_height * self.scale)
        self.screen_label.config(width=w, height=h)
        
    def _connect(self):
        """连接 WDA"""
        self.wda_url = self.url_entry.get().rstrip("/")
        self.status_var.set("正在连接...")
        
        def do_connect():
            try:
                # 检查连接
                resp = requests.get(f"{self.wda_url}/status", timeout=5)
                if resp.status_code != 200:
                    raise Exception("WDA 状态异常")
                
                # 创建会话
                session_resp = requests.post(
                    f"{self.wda_url}/session",
                    json={"capabilities": {}},
                    timeout=10
                )
                data = session_resp.json()
                self.session_id = data.get("sessionId")
                
                if not self.session_id:
                    raise Exception("无法创建会话")
                
                # 获取屏幕尺寸
                size_resp = requests.get(f"{self.wda_url}/session/{self.session_id}/window/size", timeout=5)
                size_data = size_resp.json()
                if "value" in size_data:
                    self.screen_width = size_data["value"].get("width", 375)
                    self.screen_height = size_data["value"].get("height", 667)
                
                # 在主线程更新 UI
                self.root.after(0, self._on_connected)
                
            except Exception as e:
                self.root.after(0, lambda: self._on_connect_error(str(e)))
        
        threading.Thread(target=do_connect, daemon=True).start()
        
    def _on_connected(self):
        """连接成功回调"""
        self._on_scale_change()
        self.status_var.set(f"已连接 | {self.screen_width}x{self.screen_height}")
        self.connect_btn.config(text="断开", command=self._disconnect)
        self.home_btn.config(state=tk.NORMAL)
        self.screenshot_btn.config(state=tk.NORMAL)
        
        # 开始刷新
        self.running = True
        threading.Thread(target=self._refresh_loop, daemon=True).start()
        
    def _on_connect_error(self, error):
        """连接失败回调"""
        self.status_var.set("连接失败")
        messagebox.showerror("连接失败", error)
        
    def _disconnect(self):
        """断开连接"""
        self.running = False
        self.session_id = None
        self.status_var.set("未连接")
        self.connect_btn.config(text="连接", command=self._connect)
        self.home_btn.config(state=tk.DISABLED)
        self.screenshot_btn.config(state=tk.DISABLED)
        self._create_placeholder()
        
    def _refresh_loop(self):
        """刷新循环"""
        while self.running:
            try:
                self._fetch_and_update_screen()
                fps = int(self.fps_var.get())
                time.sleep(1 / fps)
            except Exception as e:
                print(f"刷新错误: {e}")
                time.sleep(0.5)
                
    def _fetch_and_update_screen(self):
        """获取并更新屏幕 - 优化版"""
        if not self.session_id:
            return
            
        try:
            resp = requests.get(f"{self.wda_url}/screenshot", timeout=3)
            data = resp.json()
            
            if "value" in data:
                img_data = base64.b64decode(data["value"])
                img = Image.open(io.BytesIO(img_data))
                
                # 缩放图片
                new_size = (int(self.screen_width * self.scale), int(self.screen_height * self.scale))
                img = img.resize(new_size, Image.Resampling.BILINEAR)  # 使用更快的插值
                
                # 创建新的 PhotoImage
                new_photo = ImageTk.PhotoImage(img)
                
                # 在主线程更新（避免闪烁的关键）
                self.root.after(0, lambda p=new_photo: self._update_display(p))
                
        except Exception as e:
            pass  # 静默处理错误，避免刷屏
            
    def _update_display(self, photo):
        """更新显示 - 在主线程中执行"""
        self.current_photo = photo
        self.screen_label.config(image=self.current_photo)
            
    def _on_mouse_down(self, event):
        """鼠标按下"""
        self.drag_start = (event.x, event.y)
        self.drag_moved = False
        self.drag_start_time = time.time()
        
    def _on_mouse_move(self, event):
        """鼠标移动"""
        if self.drag_start:
            dx = abs(event.x - self.drag_start[0])
            dy = abs(event.y - self.drag_start[1])
            if dx > 5 or dy > 5:
                self.drag_moved = True
        
    def _on_mouse_up(self, event):
        """鼠标释放"""
        if not self.session_id or not self.drag_start:
            return
        
        # 判断是点击还是滑动
        if not self.drag_moved:
            # 点击
            x = int(self.drag_start[0] / self.scale)
            y = int(self.drag_start[1] / self.scale)
            self.status_var.set(f"点击: ({x}, {y})")
            self.executor.submit(self._do_tap, x, y)
        else:
            # 滑动
            from_x = int(self.drag_start[0] / self.scale)
            from_y = int(self.drag_start[1] / self.scale)
            to_x = int(event.x / self.scale)
            to_y = int(event.y / self.scale)
            
            # 计算滑动时间
            duration = min(time.time() - self.drag_start_time, 1.0)
            duration = max(duration, 0.1)
            
            self.status_var.set(f"滑动: ({from_x},{from_y}) → ({to_x},{to_y})")
            self.executor.submit(self._do_swipe, from_x, from_y, to_x, to_y, duration)
            
        self.drag_start = None
        self.drag_moved = False
        
    def _do_tap(self, x, y):
        """执行点击 - 异步"""
        try:
            requests.post(
                f"{self.wda_url}/session/{self.session_id}/wda/tap/0",
                json={"x": x, "y": y},
                timeout=3
            )
        except Exception as e:
            print(f"点击错误: {e}")
            
    def _do_swipe(self, from_x, from_y, to_x, to_y, duration):
        """执行滑动 - 异步"""
        try:
            requests.post(
                f"{self.wda_url}/session/{self.session_id}/wda/dragFromToForDuration",
                json={
                    "fromX": from_x,
                    "fromY": from_y,
                    "toX": to_x,
                    "toY": to_y,
                    "duration": duration
                },
                timeout=5
            )
        except Exception as e:
            print(f"滑动错误: {e}")
            
    def _press_home(self):
        """按 Home 键"""
        if not self.session_id:
            return
        self.status_var.set("返回主屏幕...")
        self.executor.submit(self._do_home)
        
    def _do_home(self):
        """执行 Home - 异步"""
        try:
            requests.post(f"{self.wda_url}/wda/homescreen", timeout=5)
            self.root.after(0, lambda: self.status_var.set("已返回主屏幕"))
        except Exception as e:
            print(f"Home 错误: {e}")
            
    def _save_screenshot(self):
        """保存截图"""
        if not self.session_id:
            return
        self.status_var.set("正在截图...")
        self.executor.submit(self._do_screenshot)
        
    def _do_screenshot(self):
        """执行截图 - 异步"""
        try:
            resp = requests.get(f"{self.wda_url}/screenshot", timeout=5)
            data = resp.json()
            
            if "value" in data:
                img_data = base64.b64decode(data["value"])
                filename = f"screenshot_{int(time.time())}.png"
                with open(filename, "wb") as f:
                    f.write(img_data)
                self.root.after(0, lambda: self.status_var.set(f"截图已保存: {filename}"))
        except Exception as e:
            self.root.after(0, lambda: self.status_var.set(f"截图失败: {e}"))
            
    def _on_close(self):
        """关闭窗口"""
        self.running = False
        self.executor.shutdown(wait=False)
        self.root.destroy()
        
    def run(self):
        """运行"""
        self.root.mainloop()


if __name__ == "__main__":
    print("=" * 50)
    print("iOS 投屏控制工具 v2.0")
    print("=" * 50)
    print("\n使用说明:")
    print("  • 点击 [连接] 开始投屏")
    print("  • 鼠标单击 = 手机点击")
    print("  • 鼠标拖动 = 手机滑动")
    print("  • 🏠 = 返回主屏幕")
    print("  • 📷 = 保存截图")
    print("=" * 50)
    
    app = iOSScreenMirror()
    app.run()

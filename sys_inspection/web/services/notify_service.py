import json
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime
import requests
from flask import current_app
from .. import db
from ..models import Setting

class NotifyService:
    
    @staticmethod
    def get_notify_config():
        config = {}
        settings = Setting.query.filter(Setting.key.like('notify_%')).all()
        for s in settings:
            config[s.key] = s.value
        return config
    
    @staticmethod
    def send_inspection_alert(alerts):
        config = NotifyService.get_notify_config()
        
        if not alerts:
            return
        
        message = NotifyService.format_alert_message(alerts)
        
        channels = json.loads(config.get('notify_channels', '[]'))
        
        for channel in channels:
            channel_type = channel.get('type')
            
            if channel_type == 'dingtalk':
                NotifyService.send_dingtalk(channel, message)
            elif channel_type == 'wecom':
                NotifyService.send_wecom(channel, message)
            elif channel_type == 'email':
                NotifyService.send_email(channel, message)
            elif channel_type == 'webhook':
                NotifyService.send_webhook(channel, message)
    
    @staticmethod
    def format_alert_message(alerts):
        lines = ["【服务器巡检告警】", f"时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}", ""]
        
        for alert in alerts[:10]:
            server_name = alert.get('server_hostname', '未知')
            status = alert.get('status', '未知')
            cpu = alert.get('cpu_usage', '-')
            mem = alert.get('memory_usage', '-')
            disk = alert.get('disk_usage', '-')
            
            lines.append(f"【{server_name}】")
            lines.append(f"  状态: {status}")
            lines.append(f"  CPU: {cpu}% | 内存: {mem}% | 磁盘: {disk}%")
            lines.append("")
        
        if len(alerts) > 10:
            lines.append(f"... 还有 {len(alerts) - 10} 条告警")
        
        return "\n".join(lines)
    
    @staticmethod
    def send_dingtalk(config, message):
        webhook = config.get('webhook')
        secret = config.get('secret')
        
        if not webhook:
            current_app.logger.warning("DingTalk webhook not configured")
            return False
        
        try:
            data = {
                "msgtype": "text",
                "text": {
                    "content": message
                }
            }
            
            if secret:
                import hmac
                import hashlib
                import base64
                import time
                import urllib.parse
                
                timestamp = str(round(time.time() * 1000))
                string_to_sign = f"{timestamp}\n{secret}"
                hmac_code = hmac.new(
                    secret.encode('utf-8'),
                    string_to_sign.encode('utf-8'),
                    digestmod=hashlib.sha256
                ).digest()
                sign = urllib.parse.quote_plus(base64.b64encode(hmac_code))
                
                webhook = f"{webhook}&timestamp={timestamp}&sign={sign}"
            
            response = requests.post(webhook, json=data, timeout=10)
            result = response.json()
            
            if result.get('errcode') == 0:
                current_app.logger.info("DingTalk notification sent successfully")
                return True
            else:
                current_app.logger.error(f"DingTalk notification failed: {result}")
                return False
        except Exception as e:
            current_app.logger.error(f"DingTalk notification error: {e}")
            return False
    
    @staticmethod
    def send_wecom(config, message):
        webhook = config.get('webhook')
        
        if not webhook:
            current_app.logger.warning("WeCom webhook not configured")
            return False
        
        try:
            data = {
                "msgtype": "text",
                "text": {
                    "content": message
                }
            }
            
            response = requests.post(webhook, json=data, timeout=10)
            result = response.json()
            
            if result.get('errcode') == 0:
                current_app.logger.info("WeCom notification sent successfully")
                return True
            else:
                current_app.logger.error(f"WeCom notification failed: {result}")
                return False
        except Exception as e:
            current_app.logger.error(f"WeCom notification error: {e}")
            return False
    
    @staticmethod
    def send_email(config, message):
        smtp_host = config.get('smtp_host')
        smtp_port = config.get('smtp_port', 25)
        smtp_user = config.get('smtp_user')
        smtp_pass = config.get('smtp_pass')
        from_addr = config.get('from_addr')
        to_addrs = config.get('to_addrs', '').split(',')
        
        if not smtp_host or not to_addrs:
            current_app.logger.warning("Email not configured properly")
            return False
        
        try:
            msg = MIMEMultipart()
            msg['From'] = from_addr or smtp_user
            msg['To'] = ', '.join(to_addrs)
            msg['Subject'] = f"【服务器巡检告警】{datetime.now().strftime('%Y-%m-%d %H:%M')}"
            
            msg.attach(MIMEText(message, 'plain', 'utf-8'))
            
            with smtplib.SMTP(smtp_host, smtp_port) as server:
                if smtp_user and smtp_pass:
                    server.starttls()
                    server.login(smtp_user, smtp_pass)
                server.sendmail(from_addr or smtp_user, to_addrs, msg.as_string())
            
            current_app.logger.info("Email notification sent successfully")
            return True
        except Exception as e:
            current_app.logger.error(f"Email notification error: {e}")
            return False
    
    @staticmethod
    def send_webhook(config, message):
        url = config.get('url')
        method = config.get('method', 'POST').upper()
        headers = json.loads(config.get('headers', '{}'))
        
        if not url:
            current_app.logger.warning("Webhook URL not configured")
            return False
        
        try:
            data = {
                "message": message,
                "timestamp": datetime.now().isoformat(),
                "source": "inspect-system"
            }
            
            if method == 'GET':
                response = requests.get(url, params=data, headers=headers, timeout=10)
            else:
                response = requests.post(url, json=data, headers=headers, timeout=10)
            
            if response.status_code < 400:
                current_app.logger.info("Webhook notification sent successfully")
                return True
            else:
                current_app.logger.error(f"Webhook notification failed: {response.status_code}")
                return False
        except Exception as e:
            current_app.logger.error(f"Webhook notification error: {e}")
            return False
    
    @staticmethod
    def send_test_notification(channel_type):
        test_message = f"【测试通知】\n时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n这是一条测试消息，请忽略。"
        
        config = NotifyService.get_notify_config()
        channels = json.loads(config.get('notify_channels', '[]'))
        
        for channel in channels:
            if channel.get('type') == channel_type:
                if channel_type == 'dingtalk':
                    return NotifyService.send_dingtalk(channel, test_message)
                elif channel_type == 'wecom':
                    return NotifyService.send_wecom(channel, test_message)
                elif channel_type == 'email':
                    return NotifyService.send_email(channel, test_message)
                elif channel_type == 'webhook':
                    return NotifyService.send_webhook(channel, test_message)
        
        return False
    
    @staticmethod
    def update_notify_channels(channels):
        from .. import db
        setting = Setting.query.filter_by(key='notify_channels').first()
        if not setting:
            setting = Setting(key='notify_channels')
            db.session.add(setting)
        
        setting.value = json.dumps(channels)
        db.session.commit()
        
        return True
from flask import Blueprint, render_template, jsonify, request
from flask_login import login_required
from ..models import Setting
from .. import db
from ..services.notify_service import NotifyService
import json
import re

settings_bp = Blueprint('settings', __name__)


def sanitize_input(value, max_length=255):
    if not value:
        return value
    value = str(value).strip()
    if len(value) > max_length:
        value = value[:max_length]
    return re.sub(r'[<>"\']', '', value)


@settings_bp.route('/')
@login_required
def list_settings():
    return render_template('web/settings.html')


@settings_bp.route('/api/list')
@login_required
def api_list():
    settings = Setting.query.all()
    
    result = {
        'threshold': {},
        'notify': {},
        'system': {}
    }
    
    for s in settings:
        if s.key.startswith('notify_'):
            result['notify'][s.key] = s.value
        elif any(s.key.startswith(p) for p in ['cpu_', 'memory_', 'disk_', 'swap_', 'connection_', 'zombie_', 'inspection_', 'report_']):
            result['threshold'][s.key] = s.value
        else:
            result['system'][s.key] = s.value
    
    return jsonify(result)


@settings_bp.route('/api/threshold', methods=['GET', 'PUT'])
@login_required
def api_threshold():
    if request.method == 'GET':
        settings = Setting.query.filter(
            Setting.key.in_([
                'cpu_usage_warning', 'cpu_usage_critical',
                'memory_usage_warning', 'memory_usage_critical',
                'disk_usage_warning', 'disk_usage_critical',
                'swap_usage_warning', 'swap_usage_critical',
                'connection_warning', 'connection_critical',
                'zombie_warning', 'zombie_critical',
                'inspection_timeout', 'report_retention_days'
            ])
        ).all()
        
        return jsonify({s.key: s.value for s in settings})
    
    else:
        data = request.get_json()
        
        if not data:
            return jsonify({'error': 'Request body is required'}), 400
        
        valid_keys = [
            'cpu_usage_warning', 'cpu_usage_critical',
            'memory_usage_warning', 'memory_usage_critical',
            'disk_usage_warning', 'disk_usage_critical',
            'swap_usage_warning', 'swap_usage_critical',
            'connection_warning', 'connection_critical',
            'zombie_warning', 'zombie_critical',
            'inspection_timeout', 'report_retention_days'
        ]
        
        for key, value in data.items():
            if key not in valid_keys:
                continue
            setting = Setting.query.filter_by(key=key).first()
            if not setting:
                setting = Setting(key=key)
                db.session.add(setting)
            setting.value = str(sanitize_input(str(value), 64))
        
        db.session.commit()
        
        return jsonify({'message': 'Settings updated successfully'})


@settings_bp.route('/api/notify', methods=['GET', 'PUT'])
@login_required
def api_notify():
    if request.method == 'GET':
        channels_setting = Setting.query.filter_by(key='notify_channels').first()
        channels = json.loads(channels_setting.value) if channels_setting else []
        
        return jsonify({
            'channels': channels
        })
    
    else:
        data = request.get_json()
        
        if not data:
            return jsonify({'error': 'Request body is required'}), 400
        
        channels = data.get('channels', [])
        
        if not isinstance(channels, list):
            return jsonify({'error': 'Channels must be a list'}), 400
        
        NotifyService.update_notify_channels(channels)
        
        return jsonify({'message': 'Notification settings updated successfully'})


@settings_bp.route('/api/notify/test/<channel_type>', methods=['POST'])
@login_required
def api_notify_test(channel_type):
    valid_types = ['dingtalk', 'wecom', 'email', 'webhook']
    safe_type = sanitize_input(channel_type, 16)
    
    if safe_type not in valid_types:
        return jsonify({'error': f'Invalid channel type. Valid types: {valid_types}'}), 400
    
    success = NotifyService.send_test_notification(safe_type)
    
    if success:
        return jsonify({'message': f'Test notification sent to {safe_type}'})
    else:
        return jsonify({'error': f'Failed to send test notification to {safe_type}'}), 400


@settings_bp.route('/api/notify/channel', methods=['POST'])
@login_required
def api_add_channel():
    data = request.get_json()
    
    if not data:
        return jsonify({'error': 'Request body is required'}), 400
    
    channel_type = sanitize_input(data.get('type', ''), 16)
    valid_types = ['dingtalk', 'wecom', 'email', 'webhook']
    
    if channel_type not in valid_types:
        return jsonify({'error': f'Invalid channel type. Valid types: {valid_types}'}), 400
    
    channels_setting = Setting.query.filter_by(key='notify_channels').first()
    channels = json.loads(channels_setting.value) if channels_setting else []
    
    channel = {
        'type': channel_type,
        'name': sanitize_input(data.get('name', channel_type), 64),
        'enabled': bool(data.get('enabled', True))
    }
    
    if channel_type == 'dingtalk':
        channel['webhook'] = sanitize_input(data.get('webhook', ''), 512)
        channel['secret'] = sanitize_input(data.get('secret', ''), 128)
    elif channel_type == 'wecom':
        channel['webhook'] = sanitize_input(data.get('webhook', ''), 512)
    elif channel_type == 'email':
        channel['smtp_host'] = sanitize_input(data.get('smtp_host', ''), 256)
        channel['smtp_port'] = int(data.get('smtp_port', 25))
        channel['smtp_user'] = sanitize_input(data.get('smtp_user', ''), 128)
        channel['smtp_pass'] = data.get('smtp_pass', '')
        channel['from_addr'] = sanitize_input(data.get('from_addr', ''), 128)
        channel['to_addrs'] = sanitize_input(data.get('to_addrs', ''), 512)
    elif channel_type == 'webhook':
        channel['url'] = sanitize_input(data.get('url', ''), 512)
        channel['method'] = sanitize_input(data.get('method', 'POST'), 8)
        channel['headers'] = data.get('headers', '{}')
    
    for i, c in enumerate(channels):
        if c.get('type') == channel_type:
            channels[i] = channel
            break
    else:
        channels.append(channel)
    
    if not channels_setting:
        channels_setting = Setting(key='notify_channels')
        db.session.add(channels_setting)
    
    channels_setting.value = json.dumps(channels)
    db.session.commit()
    
    return jsonify({'message': 'Channel added successfully', 'channel': channel})


@settings_bp.route('/api/notify/channel/<channel_type>', methods=['DELETE'])
@login_required
def api_delete_channel(channel_type):
    safe_type = sanitize_input(channel_type, 16)
    
    channels_setting = Setting.query.filter_by(key='notify_channels').first()
    if not channels_setting:
        return jsonify({'error': 'No channels configured'}), 404
    
    channels = json.loads(channels_setting.value)
    channels = [c for c in channels if c.get('type') != safe_type]
    
    channels_setting.value = json.dumps(channels)
    db.session.commit()
    
    return jsonify({'message': 'Channel deleted successfully'})
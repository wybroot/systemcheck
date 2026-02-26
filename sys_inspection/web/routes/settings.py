from flask import Blueprint, render_template, jsonify, request
from ..models import Setting
from .. import db
from ..services.notify_service import NotifyService
import json

settings_bp = Blueprint('settings', __name__)

@settings_bp.route('/')
def list_settings():
    return render_template('web/settings.html')

@settings_bp.route('/api/list')
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
        
        for key, value in data.items():
            setting = Setting.query.filter_by(key=key).first()
            if not setting:
                setting = Setting(key=key)
                db.session.add(setting)
            setting.value = str(value)
        
        db.session.commit()
        
        return jsonify({'message': 'Settings updated successfully'})

@settings_bp.route('/api/notify', methods=['GET', 'PUT'])
def api_notify():
    if request.method == 'GET':
        channels_setting = Setting.query.filter_by(key='notify_channels').first()
        channels = json.loads(channels_setting.value) if channels_setting else []
        
        return jsonify({
            'channels': channels
        })
    
    else:
        data = request.get_json()
        channels = data.get('channels', [])
        
        NotifyService.update_notify_channels(channels)
        
        return jsonify({'message': 'Notification settings updated successfully'})

@settings_bp.route('/api/notify/test/<channel_type>', methods=['POST'])
def api_notify_test(channel_type):
    success = NotifyService.send_test_notification(channel_type)
    
    if success:
        return jsonify({'message': f'Test notification sent to {channel_type}'})
    else:
        return jsonify({'error': f'Failed to send test notification to {channel_type}'}), 400

@settings_bp.route('/api/notify/channel', methods=['POST'])
def api_add_channel():
    data = request.get_json()
    
    channel_type = data.get('type')
    if not channel_type:
        return jsonify({'error': 'Channel type is required'}), 400
    
    channels_setting = Setting.query.filter_by(key='notify_channels').first()
    channels = json.loads(channels_setting.value) if channels_setting else []
    
    channel = {
        'type': channel_type,
        'name': data.get('name', channel_type),
        'enabled': data.get('enabled', True)
    }
    
    if channel_type == 'dingtalk':
        channel['webhook'] = data.get('webhook')
        channel['secret'] = data.get('secret')
    elif channel_type == 'wecom':
        channel['webhook'] = data.get('webhook')
    elif channel_type == 'email':
        channel['smtp_host'] = data.get('smtp_host')
        channel['smtp_port'] = data.get('smtp_port', 25)
        channel['smtp_user'] = data.get('smtp_user')
        channel['smtp_pass'] = data.get('smtp_pass')
        channel['from_addr'] = data.get('from_addr')
        channel['to_addrs'] = data.get('to_addrs')
    elif channel_type == 'webhook':
        channel['url'] = data.get('url')
        channel['method'] = data.get('method', 'POST')
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
def api_delete_channel(channel_type):
    channels_setting = Setting.query.filter_by(key='notify_channels').first()
    if not channels_setting:
        return jsonify({'error': 'No channels configured'}), 404
    
    channels = json.loads(channels_setting.value)
    channels = [c for c in channels if c.get('type') != channel_type]
    
    channels_setting.value = json.dumps(channels)
    db.session.commit()
    
    return jsonify({'message': 'Channel deleted successfully'})
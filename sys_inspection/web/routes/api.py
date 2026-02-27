from flask import Blueprint, jsonify, request
from flask_login import login_required, current_user
from wtforms.validators import ValidationError
from ..models import Server, Inspection, Alert, Setting
from .. import db, validate_ip
from ..services.redis_service import RedisService
import re


api_bp = Blueprint('api', __name__)


def sanitize_input(value, max_length=255):
    if not value:
        return value
    value = str(value).strip()
    if len(value) > max_length:
        value = value[:max_length]
    return re.sub(r'[<>"\']', '', value)


def validate_port(port):
    try:
        port = int(port)
        return 1 <= port <= 65535
    except (TypeError, ValueError):
        return False


@api_bp.route('/dashboard')
@login_required
def dashboard():
    cached = RedisService.get_dashboard_cache()
    if cached:
        return jsonify(cached)
    
    total_servers = Server.query.filter_by(status=1).count()
    total_inspections = Inspection.query.count()
    pending_alerts = Alert.query.filter_by(status='PENDING').count()
    
    recent_inspections = Inspection.query.order_by(Inspection.created_at.desc()).limit(5).all()
    
    status_counts = db.session.query(
        Inspection.status,
        db.func.count(Inspection.id)
    ).group_by(Inspection.status).all()
    
    result = {
        'total_servers': total_servers,
        'total_inspections': total_inspections,
        'pending_alerts': pending_alerts,
        'status_counts': dict(status_counts),
        'recent_inspections': [i.to_dict() for i in recent_inspections]
    }
    
    RedisService.set_dashboard_cache(result)
    
    return jsonify(result)


@api_bp.route('/servers')
@login_required
def list_servers():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    per_page = min(per_page, 100)
    status = request.args.get('status', type=int)
    env = request.args.get('env')
    business = request.args.get('business')
    
    query = Server.query
    
    if status is not None:
        query = query.filter_by(status=status)
    if env:
        query = query.filter_by(env=sanitize_input(env, 32))
    if business:
        safe_business = sanitize_input(business, 128)
        query = query.filter(Server.business.ilike(f'%{safe_business}%'))
    
    pagination = query.order_by(Server.created_at.desc()).paginate(
        page=page, per_page=per_page, error_out=False
    )
    
    return jsonify({
        'servers': [s.to_dict() for s in pagination.items],
        'total': pagination.total,
        'page': page,
        'per_page': per_page,
        'pages': pagination.pages
    })


@api_bp.route('/servers', methods=['POST'])
@login_required
def create_server():
    data = request.get_json()
    
    if not data:
        return jsonify({'error': 'Request body is required'}), 400
    
    ip = data.get('ip', '').strip()
    hostname = data.get('hostname', '').strip()
    
    if not ip or not hostname:
        return jsonify({'error': 'IP and hostname are required'}), 400
    
    if not validate_ip(ip):
        return jsonify({'error': 'Invalid IP address format'}), 400
    
    ssh_port = data.get('ssh_port', 22)
    if not validate_port(ssh_port):
        return jsonify({'error': 'Invalid SSH port'}), 400
    
    if Server.query.filter_by(ip=ip).first():
        return jsonify({'error': 'Server with this IP already exists'}), 400
    
    server = Server(
        hostname=sanitize_input(hostname, 64),
        ip=ip,
        ssh_port=int(ssh_port),
        ssh_user=sanitize_input(data.get('ssh_user', 'root'), 32),
        ssh_password=data.get('ssh_password', ''),
        business=sanitize_input(data.get('business'), 128),
        env=sanitize_input(data.get('env'), 32),
        services=sanitize_input(data.get('services')),
        tags=sanitize_input(data.get('tags')),
        status=data.get('status', 1)
    )
    
    db.session.add(server)
    db.session.commit()
    
    RedisService.clear_all_cache()
    
    return jsonify(server.to_dict()), 201


@api_bp.route('/servers/<int:server_id>', methods=['GET'])
@login_required
def get_server(server_id):
    cached = RedisService.get_server_cache(server_id)
    if cached:
        return jsonify(cached)
    
    server = Server.query.get_or_404(server_id)
    result = server.to_dict()
    
    RedisService.set_server_cache(server_id, result)
    
    return jsonify(result)


@api_bp.route('/servers/<int:server_id>', methods=['PUT'])
@login_required
def update_server(server_id):
    server = Server.query.get_or_404(server_id)
    data = request.get_json()
    
    if not data:
        return jsonify({'error': 'Request body is required'}), 400
    
    if 'hostname' in data:
        server.hostname = sanitize_input(data['hostname'], 64)
    if 'ssh_port' in data:
        if not validate_port(data['ssh_port']):
            return jsonify({'error': 'Invalid SSH port'}), 400
        server.ssh_port = int(data['ssh_port'])
    if 'ssh_user' in data:
        server.ssh_user = sanitize_input(data['ssh_user'], 32)
    if 'ssh_password' in data:
        server.ssh_password = data['ssh_password']
    if 'business' in data:
        server.business = sanitize_input(data['business'], 128)
    if 'env' in data:
        server.env = sanitize_input(data['env'], 32)
    if 'services' in data:
        server.services = sanitize_input(data['services'])
    if 'tags' in data:
        server.tags = sanitize_input(data['tags'])
    if 'status' in data:
        server.status = data['status']
    
    db.session.commit()
    
    RedisService.clear_all_cache()
    
    return jsonify(server.to_dict())


@api_bp.route('/servers/<int:server_id>', methods=['DELETE'])
@login_required
def delete_server(server_id):
    server = Server.query.get_or_404(server_id)
    
    db.session.delete(server)
    db.session.commit()
    
    RedisService.clear_all_cache()
    
    return jsonify({'message': 'Server deleted'})


@api_bp.route('/inspections')
@login_required
def list_inspections():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    per_page = min(per_page, 100)
    server_id = request.args.get('server_id', type=int)
    status = request.args.get('status')
    
    query = Inspection.query
    
    if server_id:
        query = query.filter_by(server_id=server_id)
    if status:
        query = query.filter_by(status=sanitize_input(status, 16))
    
    pagination = query.order_by(Inspection.created_at.desc()).paginate(
        page=page, per_page=per_page, error_out=False
    )
    
    return jsonify({
        'inspections': [i.to_dict() for i in pagination.items],
        'total': pagination.total,
        'page': page,
        'per_page': per_page,
        'pages': pagination.pages
    })


@api_bp.route('/inspections/<int:inspection_id>')
@login_required
def get_inspection(inspection_id):
    cached = RedisService.get_inspection_cache(inspection_id)
    if cached:
        return jsonify(cached)
    
    inspection = Inspection.query.options(
        db.joinedload(Inspection.items)
    ).get_or_404(inspection_id)
    result = inspection.to_dict()
    result['items'] = [i.to_dict() for i in inspection.items]
    
    RedisService.set_inspection_cache(inspection_id, result)
    
    return jsonify(result)


@api_bp.route('/inspections/run', methods=['POST'])
@login_required
def run_inspection():
    from ..services.inspector_service import InspectorService
    
    data = request.get_json()
    server_ids = data.get('server_ids', [])
    
    if not server_ids:
        return jsonify({'error': 'server_ids is required'}), 400
    
    valid_ids = []
    for sid in server_ids:
        try:
            sid = int(sid)
            if sid > 0:
                valid_ids.append(sid)
        except (TypeError, ValueError):
            pass
    
    if not valid_ids:
        return jsonify({'error': 'No valid server IDs provided'}), 400
    
    if len(valid_ids) == 1:
        result, error = InspectorService.run_inspection(valid_ids[0])
        if error:
            return jsonify({'error': error}), 500
        return jsonify(result)
    else:
        results = InspectorService.run_batch_inspection(valid_ids)
        return jsonify(results)


@api_bp.route('/alerts')
@login_required
def list_alerts():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    per_page = min(per_page, 100)
    status = request.args.get('status')
    level = request.args.get('level')
    
    query = Alert.query
    
    if status:
        query = query.filter_by(status=sanitize_input(status, 16))
    if level:
        query = query.filter_by(alert_level=sanitize_input(level, 16))
    
    pagination = query.order_by(Alert.created_at.desc()).paginate(
        page=page, per_page=per_page, error_out=False
    )
    
    return jsonify({
        'alerts': [a.to_dict() for a in pagination.items],
        'total': pagination.total,
        'page': page,
        'per_page': per_page,
        'pages': pagination.pages
    })


@api_bp.route('/alerts/<int:alert_id>/handle', methods=['POST'])
@login_required
def handle_alert(alert_id):
    alert = Alert.query.get_or_404(alert_id)
    data = request.get_json()
    
    alert.status = 'HANDLED'
    alert.handler = sanitize_input(data.get('handler', current_user.username if current_user.is_authenticated else 'system'), 32)
    alert.remark = sanitize_input(data.get('remark', ''))
    alert.handle_time = db.func.now()
    
    db.session.commit()
    
    return jsonify(alert.to_dict())


@api_bp.route('/settings')
@login_required
def list_settings():
    settings = Setting.query.all()
    return jsonify([s.to_dict() for s in settings])


@api_bp.route('/settings/<key>', methods=['GET', 'PUT'])
@login_required
def get_or_update_setting(key):
    safe_key = sanitize_input(key, 64)
    
    if request.method == 'GET':
        setting = Setting.query.filter_by(key=safe_key).first_or_404()
        return jsonify(setting.to_dict())
    else:
        setting = Setting.query.filter_by(key=safe_key).first()
        if not setting:
            setting = Setting(key=safe_key)
            db.session.add(setting)
        
        data = request.get_json()
        setting.value = sanitize_input(data.get('value'))
        setting.description = sanitize_input(data.get('description'), 256)
        
        db.session.commit()
        
        return jsonify(setting.to_dict())
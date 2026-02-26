from flask import Blueprint, jsonify, request
from ..models import Server, Inspection, Alert, Setting
from .. import db
from ..services.redis_service import RedisService

api_bp = Blueprint('api', __name__)

@api_bp.route('/dashboard')
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
def list_servers():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    status = request.args.get('status', type=int)
    env = request.args.get('env')
    business = request.args.get('business')
    
    query = Server.query
    
    if status is not None:
        query = query.filter_by(status=status)
    if env:
        query = query.filter_by(env=env)
    if business:
        query = query.filter(Server.business.ilike(f'%{business}%'))
    
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
def create_server():
    data = request.get_json()
    
    if not data.get('ip') or not data.get('hostname'):
        return jsonify({'error': 'IP and hostname are required'}), 400
    
    if Server.query.filter_by(ip=data['ip']).first():
        return jsonify({'error': 'Server with this IP already exists'}), 400
    
    server = Server(
        hostname=data.get('hostname'),
        ip=data.get('ip'),
        ssh_port=data.get('ssh_port', 22),
        ssh_user=data.get('ssh_user', 'root'),
        business=data.get('business'),
        env=data.get('env'),
        services=data.get('services'),
        tags=data.get('tags'),
        status=data.get('status', 1)
    )
    
    db.session.add(server)
    db.session.commit()
    
    RedisService.clear_all_cache()
    
    return jsonify(server.to_dict()), 201

@api_bp.route('/servers/<int:server_id>', methods=['GET'])
def get_server(server_id):
    cached = RedisService.get_server_cache(server_id)
    if cached:
        return jsonify(cached)
    
    server = Server.query.get_or_404(server_id)
    result = server.to_dict()
    
    RedisService.set_server_cache(server_id, result)
    
    return jsonify(result)

@api_bp.route('/servers/<int:server_id>', methods=['PUT'])
def update_server(server_id):
    server = Server.query.get_or_404(server_id)
    data = request.get_json()
    
    for key in ['hostname', 'ssh_port', 'ssh_user', 'business', 'env', 'services', 'tags', 'status']:
        if key in data:
            setattr(server, key, data[key])
    
    db.session.commit()
    
    RedisService.clear_all_cache()
    
    return jsonify(server.to_dict())

@api_bp.route('/servers/<int:server_id>', methods=['DELETE'])
def delete_server(server_id):
    server = Server.query.get_or_404(server_id)
    
    db.session.delete(server)
    db.session.commit()
    
    RedisService.clear_all_cache()
    
    return jsonify({'message': 'Server deleted'})

@api_bp.route('/inspections')
def list_inspections():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    server_id = request.args.get('server_id', type=int)
    status = request.args.get('status')
    
    query = Inspection.query
    
    if server_id:
        query = query.filter_by(server_id=server_id)
    if status:
        query = query.filter_by(status=status)
    
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
def get_inspection(inspection_id):
    cached = RedisService.get_inspection_cache(inspection_id)
    if cached:
        return jsonify(cached)
    
    inspection = Inspection.query.get_or_404(inspection_id)
    result = inspection.to_dict()
    result['items'] = [i.to_dict() for i in inspection.items]
    
    RedisService.set_inspection_cache(inspection_id, result)
    
    return jsonify(result)

@api_bp.route('/inspections/run', methods=['POST'])
def run_inspection():
    from ..services.inspector_service import InspectorService
    
    data = request.get_json()
    server_ids = data.get('server_ids', [])
    
    if not server_ids:
        return jsonify({'error': 'server_ids is required'}), 400
    
    if len(server_ids) == 1:
        result, error = InspectorService.run_inspection(server_ids[0])
        if error:
            return jsonify({'error': error}), 500
        return jsonify(result)
    else:
        results = InspectorService.run_batch_inspection(server_ids)
        return jsonify(results)

@api_bp.route('/alerts')
def list_alerts():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    status = request.args.get('status')
    level = request.args.get('level')
    
    query = Alert.query
    
    if status:
        query = query.filter_by(status=status)
    if level:
        query = query.filter_by(alert_level=level)
    
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
def handle_alert(alert_id):
    alert = Alert.query.get_or_404(alert_id)
    data = request.get_json()
    
    alert.status = 'HANDLED'
    alert.handler = data.get('handler')
    alert.remark = data.get('remark')
    alert.handle_time = db.func.now()
    
    db.session.commit()
    
    return jsonify(alert.to_dict())

@api_bp.route('/settings')
def list_settings():
    settings = Setting.query.all()
    return jsonify([s.to_dict() for s in settings])

@api_bp.route('/settings/<key>', methods=['GET', 'PUT'])
def get_or_update_setting(key):
    if request.method == 'GET':
        setting = Setting.query.filter_by(key=key).first_or_404()
        return jsonify(setting.to_dict())
    else:
        setting = Setting.query.filter_by(key=key).first()
        if not setting:
            setting = Setting(key=key)
            db.session.add(setting)
        
        data = request.get_json()
        setting.value = data.get('value')
        setting.description = data.get('description')
        
        db.session.commit()
        
        return jsonify(setting.to_dict())
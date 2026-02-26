from flask import Blueprint, render_template, jsonify, request
from ..models import Alert, Server
from .. import db
from datetime import datetime

alerts_bp = Blueprint('alerts', __name__)

@alerts_bp.route('/')
def list_alerts():
    return render_template('web/alerts.html')

@alerts_bp.route('/api/list')
def api_list():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    status = request.args.get('status')
    level = request.args.get('level')
    server_id = request.args.get('server_id', type=int)
    
    query = Alert.query
    
    if status:
        query = query.filter_by(status=status)
    if level:
        query = query.filter_by(alert_level=level)
    if server_id:
        query = query.filter_by(server_id=server_id)
    
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

@alerts_bp.route('/api/<int:alert_id>', methods=['GET'])
def api_get(alert_id):
    alert = Alert.query.get_or_404(alert_id)
    result = alert.to_dict()
    return jsonify(result)

@alerts_bp.route('/api/<int:alert_id>/handle', methods=['POST'])
def api_handle(alert_id):
    alert = Alert.query.get_or_404(alert_id)
    data = request.get_json()
    
    alert.status = 'HANDLED'
    alert.handler = data.get('handler', 'system')
    alert.remark = data.get('remark', '')
    alert.handle_time = datetime.utcnow()
    
    db.session.commit()
    
    return jsonify(alert.to_dict())

@alerts_bp.route('/api/<int:alert_id>/ignore', methods=['POST'])
def api_ignore(alert_id):
    alert = Alert.query.get_or_404(alert_id)
    
    alert.status = 'IGNORED'
    alert.handle_time = datetime.utcnow()
    
    db.session.commit()
    
    return jsonify(alert.to_dict())

@alerts_bp.route('/api/batch/handle', methods=['POST'])
def api_batch_handle():
    data = request.get_json()
    alert_ids = data.get('alert_ids', [])
    handler = data.get('handler', 'system')
    remark = data.get('remark', '')
    
    if not alert_ids:
        return jsonify({'error': 'No alerts selected'}), 400
    
    updated = Alert.query.filter(Alert.id.in_(alert_ids)).update(
        {
            'status': 'HANDLED',
            'handler': handler,
            'remark': remark,
            'handle_time': datetime.utcnow()
        },
        synchronize_session=False
    )
    
    db.session.commit()
    
    return jsonify({'updated': updated})

@alerts_bp.route('/api/stats')
def api_stats():
    total = Alert.query.count()
    pending = Alert.query.filter_by(status='PENDING').count()
    handled = Alert.query.filter_by(status='HANDLED').count()
    ignored = Alert.query.filter_by(status='IGNORED').count()
    
    critical = Alert.query.filter_by(alert_level='CRITICAL', status='PENDING').count()
    warning = Alert.query.filter_by(alert_level='WARNING', status='PENDING').count()
    
    return jsonify({
        'total': total,
        'pending': pending,
        'handled': handled,
        'ignored': ignored,
        'critical_pending': critical,
        'warning_pending': warning
    })
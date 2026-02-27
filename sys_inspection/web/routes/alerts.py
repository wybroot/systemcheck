from flask import Blueprint, render_template, jsonify, request
from flask_login import login_required, current_user
from ..models import Alert, Server
from .. import db
from datetime import datetime
import re


alerts_bp = Blueprint('alerts', __name__)


def sanitize_input(value, max_length=255):
    if not value:
        return value
    value = str(value).strip()
    if len(value) > max_length:
        value = value[:max_length]
    return re.sub(r'[<>"\']', '', value)


@alerts_bp.route('/')
@login_required
def list_alerts():
    return render_template('web/alerts.html')


@alerts_bp.route('/api/list')
@login_required
def api_list():
    page = request.args.get('page', 1, type=int)
    per_page = request.args.get('per_page', 20, type=int)
    per_page = min(per_page, 100)
    status = request.args.get('status')
    level = request.args.get('level')
    server_id = request.args.get('server_id', type=int)
    
    query = Alert.query
    
    if status:
        query = query.filter_by(status=sanitize_input(status, 16))
    if level:
        query = query.filter_by(alert_level=sanitize_input(level, 16))
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
@login_required
def api_get(alert_id):
    alert = Alert.query.get_or_404(alert_id)
    result = alert.to_dict()
    return jsonify(result)


@alerts_bp.route('/api/<int:alert_id>/handle', methods=['POST'])
@login_required
def api_handle(alert_id):
    alert = Alert.query.get_or_404(alert_id)
    data = request.get_json()
    
    alert.status = 'HANDLED'
    alert.handler = sanitize_input(data.get('handler', current_user.username if current_user.is_authenticated else 'system'), 32)
    alert.remark = sanitize_input(data.get('remark', ''), 1000)
    alert.handle_time = datetime.utcnow()
    
    db.session.commit()
    
    return jsonify(alert.to_dict())


@alerts_bp.route('/api/<int:alert_id>/ignore', methods=['POST'])
@login_required
def api_ignore(alert_id):
    alert = Alert.query.get_or_404(alert_id)
    
    alert.status = 'IGNORED'
    alert.handle_time = datetime.utcnow()
    
    db.session.commit()
    
    return jsonify(alert.to_dict())


@alerts_bp.route('/api/batch/handle', methods=['POST'])
@login_required
def api_batch_handle():
    data = request.get_json()
    alert_ids = data.get('alert_ids', [])
    handler = sanitize_input(data.get('handler', current_user.username if current_user.is_authenticated else 'system'), 32)
    remark = sanitize_input(data.get('remark', ''), 1000)
    
    if not alert_ids:
        return jsonify({'error': 'No alerts selected'}), 400
    
    valid_ids = [int(aid) for aid in alert_ids if str(aid).isdigit()]
    
    if not valid_ids:
        return jsonify({'error': 'No valid alert IDs'}), 400
    
    updated = Alert.query.filter(Alert.id.in_(valid_ids)).update(
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
@login_required
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
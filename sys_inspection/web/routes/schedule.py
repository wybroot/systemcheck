from flask import Blueprint, render_template, jsonify, request
from flask_login import login_required
from ..services.scheduler_service import SchedulerService
from ..models import Server

schedule_bp = Blueprint('schedule', __name__)


@schedule_bp.route('/')
@login_required
def list_schedules():
    return render_template('web/schedules.html')


@schedule_bp.route('/api/list')
@login_required
def api_list():
    jobs = SchedulerService.get_jobs()
    return jsonify({
        'jobs': jobs
    })


@schedule_bp.route('/api/add', methods=['POST'])
@login_required
def api_add():
    data = request.get_json(silent=True) or {}
    
    job_id = str(data.get('id', '')).strip()
    job_type = data.get('type')
    server_ids = data.get('server_ids')
    if isinstance(server_ids, list):
        server_ids = [int(sid) for sid in server_ids if str(sid).isdigit()]
    else:
        server_ids = None
    
    if not job_id:
        return jsonify({'error': 'Job ID is required'}), 400
    
    if job_type == 'cron':
        cron_expr = data.get('cron', '').strip()
        if not cron_expr:
            return jsonify({'error': 'Cron expression is required'}), 400
        success, message = SchedulerService.add_inspection_job(job_id, cron_expr, server_ids)
        if success:
            data['id'] = job_id
            data['type'] = 'cron'
            data['cron'] = cron_expr
    elif job_type == 'interval':
        try:
            interval = int(data.get('interval'))
        except (TypeError, ValueError):
            interval = 0
        if interval < 1:
            return jsonify({'error': 'Valid interval is required'}), 400
        success, message = SchedulerService.add_interval_job(job_id, interval, server_ids)
        if success:
            data['id'] = job_id
            data['type'] = 'interval'
            data['interval'] = interval
    else:
        return jsonify({'error': 'Invalid job type'}), 400
    
    if success:
        if server_ids is not None:
            data['server_ids'] = server_ids
        SchedulerService.save_job_config(job_id, data)
        return jsonify({'message': message})
    else:
        return jsonify({'error': message}), 400


@schedule_bp.route('/api/remove/<job_id>', methods=['DELETE'])
@login_required
def api_remove(job_id):
    success, message = SchedulerService.remove_job(job_id)
    if success:
        SchedulerService.remove_job_config(job_id)
        return jsonify({'message': message})
    else:
        return jsonify({'error': message}), 400


@schedule_bp.route('/api/pause/<job_id>', methods=['POST'])
@login_required
def api_pause(job_id):
    success, message = SchedulerService.pause_job(job_id)
    if success:
        return jsonify({'message': message})
    else:
        return jsonify({'error': message}), 400


@schedule_bp.route('/api/resume/<job_id>', methods=['POST'])
@login_required
def api_resume(job_id):
    success, message = SchedulerService.resume_job(job_id)
    if success:
        return jsonify({'message': message})
    else:
        return jsonify({'error': message}), 400


@schedule_bp.route('/api/run/<job_id>', methods=['POST'])
@login_required
def api_run(job_id):
    job = SchedulerService.get_job(job_id)
    if not job:
        return jsonify({'error': 'Job not found'}), 404
    
    from ..services.inspector_service import InspectorService
    
    job_config = SchedulerService.get_job_config(job_id)
    server_ids = job_config.get('server_ids') if job_config else None
    
    if server_ids is None:
        server_ids = [s.id for s in Server.query.filter_by(status=1).all()]
    else:
        server_ids = [int(sid) for sid in server_ids if str(sid).isdigit()]
        if not server_ids:
            server_ids = [s.id for s in Server.query.filter_by(status=1).all()]
    
    results = InspectorService.run_batch_inspection(server_ids)
    return jsonify(results)

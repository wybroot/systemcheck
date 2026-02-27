from flask import Blueprint, render_template, jsonify, request
from flask_login import login_required
from ..services.scheduler_service import SchedulerService
from ..models import Server, Setting
from .. import db
import json

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
    data = request.get_json()
    
    job_id = data.get('id', '').strip()
    job_type = data.get('type')
    server_ids = data.get('server_ids')
    
    if not job_id:
        return jsonify({'error': 'Job ID is required'}), 400
    
    if job_type == 'cron':
        cron_expr = data.get('cron', '').strip()
        if not cron_expr:
            return jsonify({'error': 'Cron expression is required'}), 400
        success, message = SchedulerService.add_inspection_job(job_id, cron_expr, server_ids)
    elif job_type == 'interval':
        interval = data.get('interval')
        if not interval or interval < 1:
            return jsonify({'error': 'Valid interval is required'}), 400
        success, message = SchedulerService.add_interval_job(job_id, interval, server_ids)
    else:
        return jsonify({'error': 'Invalid job type'}), 400
    
    if success:
        SchedulerService.save_job_config(job_id, data)
        return jsonify({'message': message})
    else:
        return jsonify({'error': message}), 400


@schedule_bp.route('/api/remove/<job_id>', methods=['DELETE'])
@login_required
def api_remove(job_id):
    success, message = SchedulerService.remove_job(job_id)
    if success:
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
    
    setting = Setting.query.filter_by(key=f'job_{job_id}').first()
    server_ids = None
    if setting:
        try:
            job_config = json.loads(setting.value)
            server_ids = job_config.get('server_ids')
        except json.JSONDecodeError:
            pass
    
    if server_ids is None:
        server_ids = [s.id for s in Server.query.filter_by(status=1).all()]
    
    result, error = InspectorService.run_batch_inspection(server_ids)
    
    if error:
        return jsonify({'error': error}), 500
    
    return jsonify(result)
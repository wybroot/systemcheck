from datetime import datetime
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger
from apscheduler.triggers.interval import IntervalTrigger
from flask import current_app
from .. import db
from ..models import Server, Setting

scheduler = BackgroundScheduler()
scheduler_started = False

class SchedulerService:
    
    @staticmethod
    def init_app(app):
        global scheduler_started
        
        if not scheduler_started:
            scheduler.init_app(app)
            scheduler.start()
            scheduler_started = True
            app.logger.info("Scheduler started")
    
    @staticmethod
    def add_inspection_job(job_id, cron_expr, server_ids=None, callback=None):
        try:
            parts = cron_expr.split()
            if len(parts) == 5:
                trigger = CronTrigger(
                    minute=parts[0],
                    hour=parts[1],
                    day=parts[2],
                    month=parts[3],
                    day_of_week=parts[4]
                )
            else:
                raise ValueError(f"Invalid cron expression: {cron_expr}")
            
            if server_ids is None:
                server_ids = [s.id for s in Server.query.filter_by(status=1).all()]
            
            scheduler.add_job(
                func=SchedulerService.run_scheduled_inspection,
                trigger=trigger,
                id=job_id,
                args=[server_ids],
                replace_existing=True
            )
            
            return True, f"Job {job_id} added successfully"
        except Exception as e:
            return False, str(e)
    
    @staticmethod
    def add_interval_job(job_id, interval_minutes, server_ids=None):
        try:
            trigger = IntervalTrigger(minutes=interval_minutes)
            
            if server_ids is None:
                server_ids = [s.id for s in Server.query.filter_by(status=1).all()]
            
            scheduler.add_job(
                func=SchedulerService.run_scheduled_inspection,
                trigger=trigger,
                id=job_id,
                args=[server_ids],
                replace_existing=True
            )
            
            return True, f"Job {job_id} added successfully"
        except Exception as e:
            return False, str(e)
    
    @staticmethod
    def remove_job(job_id):
        try:
            scheduler.remove_job(job_id)
            return True, f"Job {job_id} removed successfully"
        except Exception as e:
            return False, str(e)
    
    @staticmethod
    def pause_job(job_id):
        try:
            scheduler.pause_job(job_id)
            return True, f"Job {job_id} paused successfully"
        except Exception as e:
            return False, str(e)
    
    @staticmethod
    def resume_job(job_id):
        try:
            scheduler.resume_job(job_id)
            return True, f"Job {job_id} resumed successfully"
        except Exception as e:
            return False, str(e)
    
    @staticmethod
    def get_jobs():
        jobs = []
        for job in scheduler.get_jobs():
            jobs.append({
                'id': job.id,
                'next_run_time': job.next_run_time.isoformat() if job.next_run_time else None,
                'trigger': str(job.trigger),
                'func': job.func.__name__
            })
        return jobs
    
    @staticmethod
    def get_job(job_id):
        job = scheduler.get_job(job_id)
        if job:
            return {
                'id': job.id,
                'next_run_time': job.next_run_time.isoformat() if job.next_run_time else None,
                'trigger': str(job.trigger),
                'func': job.func.__name__
            }
        return None
    
    @staticmethod
    def run_scheduled_inspection(server_ids):
        from ..services.inspector_service import InspectorService
        from ..services.notify_service import NotifyService
        
        app = current_app._get_current_object()
        
        with app.app_context():
            app.logger.info(f"Running scheduled inspection for servers: {server_ids}")
            
            results = InspectorService.run_batch_inspection(server_ids)
            
            alerts = []
            for result in results.get('success', []):
                if result.get('status') != 'OK':
                    alerts.append(result)
            
            if alerts:
                NotifyService.send_inspection_alert(alerts)
            
            app.logger.info(f"Scheduled inspection completed. Success: {len(results.get('success', []))}, Failed: {len(results.get('failed', []))}")
    
    @staticmethod
    def load_scheduled_jobs():
        try:
            jobs_setting = Setting.query.filter_by(key='scheduled_jobs').first()
            if jobs_setting and jobs_setting.value:
                import json
                jobs = json.loads(jobs_setting.value)
                for job in jobs:
                    if job.get('type') == 'cron':
                        SchedulerService.add_inspection_job(
                            job['id'],
                            job['cron'],
                            job.get('server_ids')
                        )
                    elif job.get('type') == 'interval':
                        SchedulerService.add_interval_job(
                            job['id'],
                            job['interval'],
                            job.get('server_ids')
                        )
        except Exception as e:
            current_app.logger.error(f"Failed to load scheduled jobs: {e}")
    
    @staticmethod
    def save_job_config(job_id, job_config):
        try:
            import json
            from .. import db
            
            jobs_setting = Setting.query.filter_by(key='scheduled_jobs').first()
            if not jobs_setting:
                jobs_setting = Setting(key='scheduled_jobs', value='[]')
                db.session.add(jobs_setting)
            
            jobs = json.loads(jobs_setting.value) if jobs_setting.value else []
            
            for i, job in enumerate(jobs):
                if job.get('id') == job_id:
                    jobs[i] = job_config
                    break
            else:
                jobs.append(job_config)
            
            jobs_setting.value = json.dumps(jobs)
            db.session.commit()
            
            return True
        except Exception as e:
            current_app.logger.error(f"Failed to save job config: {e}")
            return False
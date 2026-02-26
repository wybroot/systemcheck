from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
import redis
import logging

db = SQLAlchemy()
migrate = Migrate()
redis_client = None
scheduler = None

def create_app(config_name='default'):
    from web.config import config
    
    app = Flask(__name__,
                template_folder='templates',
                static_folder='static')
    
    app.config.from_object(config[config_name])
    
    db.init_app(app)
    migrate.init_app(app, db)
    
    global redis_client
    try:
        redis_client = redis.from_url(app.config['REDIS_URL'], decode_responses=True)
    except Exception as e:
        app.logger.warning(f"Redis connection failed: {e}")
        redis_client = None
    
    from web.routes.main import main_bp
    from web.routes.api import api_bp
    from web.routes.servers import servers_bp
    from web.routes.inspections import inspections_bp
    from web.routes.schedule import schedule_bp
    from web.routes.alerts import alerts_bp
    from web.routes.settings import settings_bp
    
    app.register_blueprint(main_bp)
    app.register_blueprint(api_bp, url_prefix='/api')
    app.register_blueprint(servers_bp, url_prefix='/servers')
    app.register_blueprint(inspections_bp, url_prefix='/inspections')
    app.register_blueprint(schedule_bp, url_prefix='/schedule')
    app.register_blueprint(alerts_bp, url_prefix='/alerts')
    app.register_blueprint(settings_bp, url_prefix='/settings')
    
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    
    @app.context_processor
    def inject_globals():
        return {
            'app_name': '服务器巡检系统'
        }
    
    with app.app_context():
        from web.services.scheduler_service import SchedulerService
        global scheduler
        scheduler = SchedulerService
        SchedulerService.init_app(app)
        SchedulerService.load_scheduled_jobs()
    
    return app